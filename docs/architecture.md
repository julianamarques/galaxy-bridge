# Galaxy Bridge architecture

Status: **proposal** — nothing here is built yet. Today Galaxy Bridge talks to the phone through `adb` (Wireless debugging or USB debugging). This document describes the move to a companion Android app, so that the phone no longer needs Developer options.

## Goals

- **No Developer options.** The user installs Galaxy Bridge on the Mac and on the Galaxy, pairs them with a QR code, and that is it. Nothing turns off when the phone restarts or changes networks.
- **Always connected.** While both devices are on the same Wi-Fi network, the connection comes back on its own, without opening either app.
- **Features that adb cannot do well:** incoming calls with the caller's name, answering and declining from the Mac, notifications with replies.
- **Local only.** Nothing leaves the local network. There is no server and no account.
- **No paid Apple Developer account.** Everything on the Mac works with local signing.

### Non-goals

- **Call audio on the Mac.** Android only lets system apps capture or inject the audio of a phone call, and macOS cannot connect to a phone as a Bluetooth hands-free device. Calls are answered from the Mac and the conversation stays on the phone or the earbuds connected to it.
- **Screen mirroring.** That stays in Galaxy Mirror, which needs `adb` to inject touches.
- **Internet relay** (using the phone when it is away from the Mac). Possible later, out of scope now.

## Overview

```
 ┌──────────────── Mac ────────────────┐            ┌────────────── Galaxy ──────────────┐
 │ Galaxy Bridge (menu bar app)        │            │ Galaxy Bridge (Android app)         │
 │                                     │            │                                     │
 │  UI: menu, setup, settings          │            │  UI: onboarding, permissions        │
 │  BridgeServer ── NWListener (TLS) ◄─┼── Wi-Fi ───┼─ BridgeClient ── TLS socket         │
 │  Bonjour: _galaxybridge._tcp ───────┼─ mDNS ────►│  NsdManager discovery               │
 │  PairingStore (pinned certificates) │            │  BridgeService (foreground service) │
 │                                     │            │   ├─ StatusMonitor (battery, SIM)   │
 │  Features: status, calls,           │            │   ├─ CallMonitor (Telecom)          │
 │  notifications                      │            │   └─ NotificationRelay (listener)   │
 └─────────────────────────────────────┘            └─────────────────────────────────────┘
```

The **Mac is the server** and the **phone is the client**:

- The Mac app is always running in the menu bar and its address barely changes. It advertises a Bonjour service and listens for connections.
- The phone decides when to connect, which fits Android's battery rules. It finds the Mac through mDNS and reconnects when Wi-Fi comes back, with the last known address as a fallback when multicast is unreliable.

## Repository layout

One repository for both apps, so a protocol change and both of its implementations land in the same pull request.

```
galaxy-bridge/
├── macos/                Swift package (what is at the root today)
│   ├── Sources/GalaxyBridge/
│   ├── Sources/BridgeProtocol/   messages, framing, TLS identity — no UI
│   └── Tests/
├── android/              Gradle project (Kotlin, Jetpack Compose)
│   └── app/
├── protocol/
│   ├── protocol.md       message reference
│   └── fixtures/         one JSON file per message, decoded by both test suites
└── docs/
```

`GalaxyKit` (the adb code shared with Galaxy Mirror) leaves Galaxy Bridge once the Android app covers status and calls. It can live on in Galaxy Mirror or become its own package.

## Connection

### Discovery

- The Mac advertises `_galaxybridge._tcp` with `NWListener.service`. The TXT record carries the protocol version and the Mac's ID (the SHA-256 of its certificate, shortened). The phone only connects to Macs it is paired with.
- The phone browses with `NsdManager` while `BridgeService` runs, holding a `WifiManager.MulticastLock` only while it browses.
- After every successful connection the phone stores the Mac's IP address and port, and tries it first next time.
- The Mac's `Info.plist` adds `_galaxybridge._tcp` to `NSBonjourServices`. The Local Network permission it already asks for covers listening and advertising.

### Transport security

TLS 1.3 with **mutual authentication and pinned self-signed certificates** — the same model as KDE Connect, with no certificate authority involved.

- **Mac identity:** a P-256 key and a self-signed certificate, generated on first launch with [swift-certificates](https://github.com/apple/swift-certificates). They are stored in `~/Library/Application Support/Galaxy Bridge/identity` with `0600` permissions. The Keychain is avoided on purpose: with local (ad-hoc) signing, every new build has a different signature and macOS would ask for keychain access after each update. It can move to the Keychain once the app has a Developer ID.
- **Phone identity:** a P-256 key in the Android Keystore (it never leaves the secure hardware), which generates its own self-signed certificate.
- **Mac side:** `sec_protocol_options` requires a client certificate and checks it in the verify block against the pinned fingerprints, instead of the system trust store.
- **Phone side:** a custom `X509TrustManager` accepts only the pinned fingerprint of the paired Mac. The Keystore key is the client certificate.

### Pairing

Same flow as Galaxy Mirror, the other way around: the **Mac shows the QR code** and the phone scans it.

1. The user clicks **Add Galaxy** on the Mac. The Mac creates a one-time token (128 random bits, valid for 2 minutes) and shows a QR code:
   `galaxybridge://pair?v=1&host=192.168.1.20&port=52800&fp=<sha256 of the Mac certificate>&token=<token>`
2. The phone scans it with the [Google code scanner](https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner) (Play services; no camera permission needed).
3. The phone opens a TLS connection. It checks that the Mac's certificate matches `fp`, and sends its own certificate during the handshake.
4. The phone sends `pair.request` with the token, its name and its model. The Mac checks the token, stores the phone's fingerprint and answers `pair.accepted`. The token cannot be used again.
5. From then on, every connection is mutually pinned. **Forget** on either side removes the other's fingerprint.

If the camera cannot be used, the Mac also shows a six-digit code that the phone can type. The Mac's address comes from Bonjour, and the code stands in for the token. The phone then shows the first characters of the Mac's fingerprint and the user confirms they match the Mac's screen.

### Framing and messages

Each message is a 4-byte big-endian length followed by UTF-8 JSON:

```json
{ "type": "call.incoming", "id": "7f3a…", "body": { "callId": "c1", "number": "+5586999990001", "name": "Juliana" } }
```

- `id` is set on requests. The answer carries the same `id` in `replyTo`.
- Unknown `type`s are ignored, so either app can be updated first. `hello` carries the protocol version. A major version change refuses the connection and asks the user to update the older app.
- Messages are capped at 1 MB. Files, in a later phase, will use a separate TLS connection per transfer, so they never block calls or notifications.
- Swift uses `Codable` and Kotlin uses `kotlinx.serialization`. Each message has a fixture in `protocol/fixtures/` that both test suites decode and re-encode.

Keep-alive: the phone sends `ping` every 30 seconds and the Mac answers `pong`. With no traffic for 75 seconds, either side drops the connection and the phone reconnects.

## Messages

| Type | Direction | Body |
|---|---|---|
| `hello` | both | protocol version, app version, device name, model |
| `pair.request` / `pair.accepted` / `pair.rejected` | phone → Mac / Mac → phone | token, name, model / reason |
| `status` | phone → Mac | battery level, charging, network country, SIM country |
| `call.place` | Mac → phone | number (E.164, already normalized on the Mac) |
| `call.incoming` | phone → Mac | call ID, number, contact name |
| `call.state` | phone → Mac | call ID, `ringing` / `active` / `ended` |
| `call.answer` / `call.decline` / `call.end` | Mac → phone | call ID |
| `notification.posted` | phone → Mac | key, app, title, text, time, icon ID, actions (ID, title, accepts reply) |
| `notification.removed` | phone → Mac | key |
| `notification.action` | Mac → phone | key, action ID, reply text |
| `notification.dismiss` | Mac → phone | key |
| `icon.request` / `icon` | Mac → phone / phone → Mac | icon ID / PNG data, cached on the Mac per app |
| `ping` / `pong` | both | — |

`status` is sent on connect and whenever something changes, instead of every minute.

## Android app

- **Language and UI:** Kotlin, Jetpack Compose with Material 3. Minimum Android 11 (API 30), like Galaxy Mirror. Package ID `com.julianamarques.galaxybridge`.
- **`BridgeService`:** a foreground service of type `connectedDevice`, with a silent ongoing notification ("Connected to MacBook Air"). It declares `FOREGROUND_SERVICE_CONNECTED_DEVICE`, plus one of the permissions the [service type requires](https://developer.android.com/guide/components/fg-service-types) (the network ones, such as `CHANGE_WIFI_MULTICAST_STATE`, which discovery needs anyway; confirm against the list in Phase 0). It starts on boot (`RECEIVE_BOOT_COMPLETED`) and when the app is opened.
- **`StatusMonitor`:** battery from `ACTION_BATTERY_CHANGED`, countries from `TelephonyManager` (`networkCountryIso`, `simCountryIso`).
- **`CallMonitor`:** (approach confirmed in Phase 0, see below)
  - Call state through `TelephonyCallback` (`READ_PHONE_STATE`).
  - Caller name from the dialer's call notification (`com.samsung.android.incallui`, `Notification.CallStyle`): its title is the contact name and its `callPerson` carries the number as a `tel:` URI. The number is also available from `PhoneStateListener` with `READ_CALL_LOG`, in national format (`086…`), so the Mac normalizes it with PhoneNumberKit.
  - Answer and decline with `TelecomManager.acceptRingingCall()` and `endCall()` (`ANSWER_PHONE_CALLS`). Both are deprecated since Android 10 but work on One UI 9; `endCall()` also hangs up an active call.
  - Outgoing calls with `TelecomManager.placeCall()` (`CALL_PHONE`). It does not start an activity, so Android's limits on starting activities from the background don't apply.
- **`NotificationRelay`:** a `NotificationListenerService`. It skips ongoing, silent and group-summary notifications and Galaxy Bridge's own. Replies fill the action's `RemoteInput`.
- **Onboarding:** one screen per permission, in the order the features need them, each explaining why. It ends by asking to set the battery to **Unrestricted** (One UI's "Sleeping apps" would otherwise kill the service) and to scan the Mac's QR code.

## Mac app

- **`BridgeProtocol`** (new library target, no UI): message types, framing, the TLS identity and fingerprints, the pairing store. Unit-tested with the fixtures.
- **`BridgeServer`:** `NWListener` with TLS. It accepts one connection per paired phone, publishes the connection state and routes messages to the features.
- **UI:** the same menu and settings as today. Setup changes from "turn on Wireless debugging" to "install Galaxy Bridge on the Galaxy and scan this code". The APK link is shown as a QR code too.
- **Calls:** an incoming call shows a `UNUserNotificationCenter` notification with **Answer** and **Decline** actions (time-sensitive category). The existing dialer and `tel:` handler send `call.place` instead of running adb.
- **Notifications:** mirrored into Notification Center under the app's name and icon, with **Reply** as a text-input action. Removing one on either side removes it on the other.

## Distribution

- **Android:** a signed APK on GitHub Releases, like Galaxy Mirror's DMG. The signing keystore must be backed up: an APK signed with a different key cannot update the installed app.
- **Restricted settings:** Android blocks notification access for apps installed outside an app store until the user taps **⋮ › Allow restricted settings** on the app's info page. Since Android 15 this is enforced more strictly (Enhanced Confirmation Mode). Onboarding has to walk the user through it, and it needs testing on the S25 with One UI 8.
- **Google Play, later:** reading call logs, notification access and battery exemptions all go through Play policy review. That is a separate decision, not needed for the first versions.
- **Android 17 local network permission:** apps targeting API 37 must request `ACCESS_LOCAL_NETWORK` at runtime ([docs](https://developer.android.com/privacy-and-security/local-network-permission)). The app targets API 36 at first and adds the request when it moves to 37.

## Phases

### Phase 0 — Spikes on the Galaxy S25

Throwaway code to answer the riskiest questions before committing to the design:

1. ~~Does `acceptRingingCall()` / `endCall()` work on One UI, and do the dialer's call-notification actions work as a fallback?~~ Answered, see [Phase 0 results](#phase-0-results).
2. Does the foreground service survive a night with the screen off and the battery set to Unrestricted?
3. Can an Android Keystore key be the client certificate in a TLS 1.3 connection to `NWListener`, with both sides pinning?
4. How hard is "Allow restricted settings" for a sideloaded APK on One UI 8?

### Phase 0 results

Galaxy S25 (SM-S931B), Android 17, One UI 9, 2026-10-12. Spike: `spikes/phase0-calls`.

**Calls** — four incoming calls, one method each, run 3 seconds after the phone started ringing, with the app in the background:

| Method | Result |
|---|---|
| `TelecomManager.acceptRingingCall()` | Answered in about 0.2 s. `endCall()` 5 s later hung up the active call. |
| `TelecomManager.endCall()` while ringing | Declined right away (returned `true`). |
| Dialer notification's answer action | Not available. |
| Dialer notification's decline action | Not available. |

- Samsung's dialer posts a `CallStyle` notification with `callType = 2` (ongoing) even while ringing. Its only action is **Desligar** (hang up), with no `answerIntent` or `declineIntent`, so the notification fallback is dropped from the design. The Telecom methods are the only way to answer and decline.
- The notification arrives 0.3–0.5 s after the ringing state. Its title is the contact name ("Maria"). Its `callPerson` has the name immediately and the `tel:` number in the second update, about 0.2 s later.
- `PhoneStateListener` (deprecated) reports the number with the ringing state when `READ_CALL_LOG` is granted. `TelephonyCallback` never does.
- **Outgoing call from the background:** `TelecomManager.placeCall()` with an E.164 number (`+55…`), triggered by a broadcast while the app's process had just been started in the background, dialed right away (off-hook in 0.1 s): the other phone rang, and the S25 showed the dialer's in-call screen, as expected. `endCall()` 15 s later ended it.
- The app's process stayed alive for more than two hours in the background with only the notification listener bound and no foreground service, which is encouraging for question 2 but is not the night-long test.

### Phase 1 — Connection and status

Repository restructure, `BridgeProtocol`, QR pairing, `BridgeServer` / `BridgeService`, reconnection, `status` (battery and countries). Calls from the Mac move from adb to `call.place`.

Done when: after a phone restart and a Wi-Fi change, the menu shows the battery again within 30 seconds, without opening the Android app.

### Phase 2 — Incoming calls

`CallMonitor`, the Mac's call notification with Answer and Decline, the call state in the menu (with "End call").

Done when: a call to the S25 shows the contact's name on the Mac within 2 seconds and can be answered and declined from there.

### Phase 3 — Notifications

`NotificationRelay`, icons, replies, removal on both sides, and a per-app filter in the settings of both apps.

### Phase 4 — Files and clipboard

"Send to Galaxy" from the Finder's Services menu, files from the phone's share sheet to the Mac, and clipboard sync with an explicit action (no background sync of what the user copies).

## Testing

- **Protocol:** every message fixture is decoded and re-encoded by `swift test` and by the Android unit tests, so the two implementations can't drift apart.
- **Mac:** unit tests for framing, pairing (token expiry, reuse, wrong fingerprint) and the message router.
- **Android:** unit tests for the monitors' parsing, instrumented tests for `BridgeService`'s reconnection.
- **Manual checklist on the S25** for each phase, covering restart, Wi-Fi changes, screen off, and battery saver.

## Open questions

- **App name on the phone:** "Galaxy Bridge" as well, or something that says what it does from the phone's point of view ("Galaxy Bridge for Mac")?
- **More than one Mac per phone, or more than one phone per Mac.** The protocol allows both. The first versions will support one of each, to keep the UI simple.
- **One UI's direct voicemail.** "Correio de voz direto" is a One UI feature the user turns on in the Phone app's settings (it is on for the user's S25). When it is on and a call goes unanswered for about 20 seconds, it picks the call up to record a message: the call state becomes off-hook and the dialer's notification text changes to "Correio de voz direto" (confirmed with the user). Phase 2 must tell this apart from the user answering, so the Mac shows "went to voicemail" instead of an answered call. The notification text is localized, so look for a sturdier signal first (a notification extra, the call's audio route, or the order of events), with the text as a last resort.
- **Bluetooth LE presence.** Android's `CompanionDeviceManager` can wake the app when a paired device comes near, and an association also exempts the app from some background limits. It would need the Mac to advertise over BLE. Worth evaluating after Phase 2.
