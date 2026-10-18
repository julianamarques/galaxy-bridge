# Galaxy Bridge architecture

Status: **Phase 1 done** (2026-10-17). The Mac and the Android app connect, pair and stay connected, with status and calls from the Mac; the `adb` connection remains as an alternative. Phase 2 onwards is still a proposal. This document describes the move to a companion Android app, so that the phone no longer needs Developer options.

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
├── macos/                Swift package
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

- **Mac identity:** a P-256 key and a self-signed certificate, generated on first launch with [swift-certificates](https://github.com/apple/swift-certificates). They are stored in `~/Library/Application Support/Galaxy Bridge/identity` with `0600` permissions and turned into a `SecIdentity` in memory with `SecIdentityCreate` (confirmed in Phase 0). The Keychain is avoided on purpose: with local (ad-hoc) signing, every new build has a different signature and macOS would ask for keychain access after each update. It can move to the Keychain once the app has a Developer ID.
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

Keep-alive: the **Mac** sends `ping` every 2 minutes and the phone answers `pong`. Phase 0 showed that the phone's own timers are delayed by minutes while the CPU sleeps, that a sleeping phone can go quiet for up to 15 minutes, and that waking it every minute costs battery. So the Mac pings every 2 minutes, even while the phone is sending status updates (the phone counts only what it receives, so it would otherwise give up after 6 minutes), and gives the phone 60 seconds to answer: a network check took 48 s once in light idle. A phone that has really gone (battery dead, out of Wi-Fi) is noticed within about 3 minutes. A phone that shuts down or restarts closes the connection first, so the Mac notices at once. The Mac app does the same when it quits, waiting up to 1 second for the close to go out: Network.framework runs TCP inside the app's process, so once the process is gone nothing answers the phone, and it would wait out its own 6 minutes. The phone drops the connection after 6 minutes without any message. The phone reconnects when it notices the drop, or when `ConnectivityManager` reports a network change. The exact intervals are in [protocol.md](../protocol/protocol.md).

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
- **`BridgeService`:** a foreground service of type `connectedDevice`, with a silent ongoing notification ("Connected to MacBook Air"). It declares `FOREGROUND_SERVICE_CONNECTED_DEVICE`, plus one of the permissions the [service type requires](https://developer.android.com/guide/components/fg-service-types) (the network ones, such as `CHANGE_WIFI_MULTICAST_STATE`, which discovery needs anyway; confirm against the list in Phase 0). It starts on boot (`RECEIVE_BOOT_COMPLETED`; Android 15 forbids starting some service types from that broadcast, but not `connectedDevice`) and when the app is opened. It holds no wakelock.
- **`StatusMonitor`:** battery from `ACTION_BATTERY_CHANGED`, countries from `TelephonyManager` (`networkCountryIso`, `simCountryIso`).
- **`CallMonitor`:** (approach confirmed in Phase 0, see below)
  - Call state through `TelephonyCallback` (`READ_PHONE_STATE`).
  - Caller name and number from the dialer's call notification (`com.samsung.android.incallui`, `Notification.CallStyle`): its title is the contact name and its `callPerson` carries the number as a `tel:` URI, in national format (`086…`), so the Mac normalizes it with PhoneNumberKit. `PhoneStateListener` with `READ_CALL_LOG` also has the number, but that permission is restricted on Google Play, so the app doesn't ask for it.
  - Answer and decline with `TelecomManager.acceptRingingCall()` and `endCall()` (`ANSWER_PHONE_CALLS`). Both are deprecated since Android 10 but work on One UI 9; `endCall()` also hangs up an active call.
  - Outgoing calls with `TelecomManager.placeCall()` (`CALL_PHONE`). It does not start an activity, so Android's limits on starting activities from the background don't apply.
- **`NotificationRelay`:** a `NotificationListenerService`. It skips ongoing, silent and group-summary notifications and Galaxy Bridge's own. Replies fill the action's `RemoteInput`.
- **Onboarding:** one screen per permission, in the order the features need them, each explaining why. It ends by asking to set the battery to **Unrestricted** (One UI's "Sleeping apps" would otherwise kill the service) and to scan the Mac's QR code.

## Mac app

- **`BridgeProtocol`** (new library target, no UI): message types, framing, the TLS identity and fingerprints, the pairing store, and `BridgeServer`. Unit-tested with the fixtures, and end to end with a test TLS client.
- **`BridgeServer`:** `NWListener` with TLS. It accepts one connection per paired phone, publishes the connection state and routes messages to the features.
- **UI:** the same menu and settings as today. Setup changes from "turn on Wireless debugging" to "install Galaxy Bridge on the Galaxy and scan this code". The APK link is shown as a QR code too.
- **Calls:** an incoming call shows a `UNUserNotificationCenter` notification with **Answer** and **Decline** actions (time-sensitive category). The existing dialer and `tel:` handler send `call.place` instead of running adb.
- **Notifications:** mirrored into Notification Center under the app's name and icon, with **Reply** as a text-input action. Removing one on either side removes it on the other.

## Distribution

**A store is required.** Phase 0 showed that a plain APK can't be the way users install the Android app in Brazil (see [results](#phase-0-results)):

- **Play Protect's enhanced fraud protection** (in Brazil since 2024) blocks apps installed from a file manager, browser or messaging app when they declare sensitive permissions, including **notification access**. The dialog has no "install anyway" option.
- **Android developer verification** (enforced in Brazil, Indonesia, Singapore and Thailand since 2026-09-30, worldwide from 2027) only lets apps from unregistered developers install through an "advanced flow": a Developer options toggle, a restart and a 24-hour wait. Google's [limited distribution](https://developer.android.com/developer-verification/guides) option allows up to 20 devices.
- **Restricted settings** (Android 13+, stricter since Android 15) would then still block notification access until the user allows it on the app's info page.

Installs from a store skip all three. Installs through `adb` are exempt too, which is fine for development but not for users.

Options, to decide before Phase 1 ships to anyone else:

| Store | Cost | Notes |
|---|---|---|
| Google Play | US$ 25, once | Reaches every Android phone. New personal accounts must run a closed test (12 testers for 14 days) before publishing. Policy review for notification access, `ANSWER_PHONE_CALLS` and the battery exemption. `READ_CALL_LOG` falls under the SMS and Call Log policy, so the app gets the caller's number from the dialer's notification instead. |
| Galaxy Store | Free seller account | Fits a Galaxy-focused app and is preinstalled on every Galaxy. Samsung reviews each release. |

Whatever the store, keep the signing key backed up: an app signed with a different key cannot update the installed one.

- **Android 17 local network permission:** apps targeting API 37 must request `ACCESS_LOCAL_NETWORK` at runtime ([docs](https://developer.android.com/privacy-and-security/local-network-permission)). The app targets API 36 at first and adds the request when it moves to 37.

## Phases

### Phase 0 — Spikes on the Galaxy S25

Throwaway code to answer the riskiest questions before committing to the design:

1. ~~Does `acceptRingingCall()` / `endCall()` work on One UI, and do the dialer's call-notification actions work as a fallback?~~ Answered, see [Phase 0 results](#phase-0-results).
2. ~~Does the foreground service survive a night with the screen off and the battery set to Unrestricted?~~ Yes, with the network working during Doze, see [Phase 0 results](#phase-0-results).
3. ~~Can an Android Keystore key be the client certificate in a TLS 1.3 connection to `NWListener`, with both sides pinning?~~ Yes, see [Phase 0 results](#phase-0-results).
4. ~~How hard is "Allow restricted settings" for a sideloaded APK on One UI 8?~~ Moot: Play Protect blocks the install itself in Brazil, see [Phase 0 results](#phase-0-results) and [Distribution](#distribution).

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
- The app's process stayed alive for more than two hours in the background with only the notification listener bound and no foreground service.

**Background survival** — spike `spikes/phase0-background`: a `connectedDevice` foreground service without a wakelock, logging a row every 60 seconds, battery set to Unrestricted, 2026-10-12 21:46 to 2026-10-13 ~19:00:

- **One UI never killed it.** It ran for over 20 hours, through a night and a day of normal use, until the battery ran out. After the phone was recharged and turned on, the service only came back when it was started again, as expected without a boot receiver.
- **Timers stop while the CPU sleeps.** During the day, with the screen off, the 60-second timer fired 5 to 14 minutes late. So the phone can't keep the connection alive with its own timer: the **Mac sends the keep-alive pings** and the phone answers. An incoming packet over Wi-Fi wakes the phone, and system events (an incoming call, a new notification) wake the app on their own.
- The first night doesn't say much about Doze or battery: the phone wasn't on Wi-Fi and was sharing its connection with the Mac, which keeps the CPU awake and drains the battery on its own. During the day it was on mobile data under normal use, so the drain there can't be told apart from the user's own.

**Second night** — same service, still running from 2026-10-13 20:33 (11 hours by morning, never restarted), on home Wi-Fi, no hotspot, unplugged at 22:53 with 100%. Screen off from 00:52 to 07:35:

- **The network works during deep Doze.** Doze from 01:54 to 05:45, with maintenance windows at 02:54 and 04:56. All 228 checks inside Doze (a TCP connection to the router) succeeded in under 70 ms, and the timer fired every 60 s on time. The app is on the Doze allowlist because the battery is set to Unrestricted (`dumpsys deviceidle whitelist` lists it as `user`), which is what lets it use the network; without that, Doze cuts it off. So the onboarding step for Unrestricted is required, not optional.
- **After Doze, light idle is the bumpy part.** From 05:45 until the screen came on, the 60-second timer fired every 2.5 to 3.5 minutes, and once the phone went quiet for 15 minutes (06:40 to 06:54, after a check that took 48 s). The Mac must give a slow `pong` time to arrive, and the phone must reconnect on its own when it wakes and finds the connection gone.
- **Battery:** 91% to 73% over 6.7 hours with the screen off, about **2.7% per hour** (2.6%/h inside Doze). That is well above what an idle phone usually loses, and the likely cause is the spike itself, waking the CPU and the Wi-Fi radio every minute. There was no baseline night without the spike, so the exact share isn't known. The real app has no timer of its own: the cost depends on how often the Mac pings, which Phase 1 should set to a few minutes and measure again.
- One network failure (a 3-second timeout) and one minute without Wi-Fi in the whole run, both before unplugging, with the screen on.

**Sideloading** — the calls spike's APK, copied to Downloads and opened with My Files (the way a user installs an APK downloaded from GitHub), was blocked by Google Play Protect: "O app foi bloqueado para proteger seu dispositivo — Esse app pode pedir acesso a dados sensíveis", with only an "Entendi" button. That is the enhanced fraud protection, triggered by the app's notification listener. The same APK installs fine through `adb`.

**Mutual TLS** — spike `spikes/phase0-tls`, the phone connecting to the Mac through `adb reverse`:

- The Mac's identity is a P-256 key and a self-signed certificate made with swift-certificates 1.21, kept in files, and turned into a `SecIdentity` **in memory** with `SecIdentityCreate(_:_:_:)` (public since macOS 10.12). No Keychain and no PKCS#12, so the macOS 14 minimum stays.
- The phone's key lives in the Android Keystore (P-256, digests `NONE` and SHA-2), which also generates its self-signed certificate. A custom `X509ExtendedKeyManager` offers it as the client certificate, and a custom `X509ExtendedTrustManager` accepts only the pinned Mac.
- Result: TLS 1.3 with `TLS_AES_128_GCM_SHA256`, each side seeing the other's expected fingerprint, and length-prefixed JSON going both ways.
- A wrong Mac fingerprint on the phone fails the handshake before any data is sent. A Mac pinned to another phone rejects it with a `certificate_unknown` alert.
- **Design note:** in TLS 1.3 the client finishes its handshake before the server has checked the client certificate, so on the phone `startHandshake()` succeeds even when the Mac is about to reject it. The phone must treat the connection as established only after the Mac's `hello` arrives.

**Foreground service type** — `startForeground()` with `FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE` works with `CHANGE_WIFI_MULTICAST_STATE` as the declared prerequisite (spike `spikes/phase0-background`).

### Phase 1 — Connection and status

Repository restructure, `BridgeProtocol`, QR pairing, `BridgeServer` / `BridgeService`, reconnection, `status` (battery and countries). Calls from the Mac move from adb to `call.place`.

Done when: after a phone restart and a Wi-Fi change, the menu shows the battery again within 30 seconds, without opening the Android app.

### Phase 1 results

Galaxy S25, 2026-10-14 to 2026-10-17, MacBook on the power adapter, both on home Wi-Fi. Every case without opening the Android app:

| Case | Result |
|---|---|
| Pairing with the QR code | Paired and connected on the first try. |
| Battery and calls | Battery in the menu; two `call.place` dialed on the phone. |
| Mac app quits and reopens (3 times) | The phone noticed at once each time and reconnected 2 to 5 s after the app reopened. |
| Phone Wi-Fi off for 10 s | Reconnected 2 s after Wi-Fi came back. |
| Phone restarts from the power menu | The Mac noticed in 1.5 s. The phone reconnected about 31 s after the first unlock. |
| Phone Wi-Fi off for 3+ minutes | The Mac dropped the phone after 3 min 17 s; reconnected 3 s after Wi-Fi came back. |
| Mac sleeps for 1 minute | The connection survived; no reconnection needed. |
| Mac sleeps for 16 minutes | Already connected when the Mac woke. |
| Mac on battery sleeps for an hour | Battery back in the menu 1 min 53 s after waking; 3 s after the fix below (21-minute sleep). |

- **After a restart the app only starts after the first unlock.** Android delivers `BOOT_COMPLETED` once the user unlocks; before that the app's storage is encrypted. The 31 s after unlocking are the system's queue of boot broadcasts: the app connected half a second after it was started. Starting before the first unlock would mean keeping the pairing in device-protected storage; not worth it for now.
- **Bugs found and fixed during the tests:** the Mac took up to 7.5 minutes to notice a phone that had restarted (now: the phone closes the connection on `ACTION_SHUTDOWN`, and the Mac waits 60 s for a `pong`); the phone dropped the connection every 6 minutes while charging, because the Mac only pinged after 2 minutes of silence and the phone kept sending status; and the Mac app's quit could beat its own close message (now it waits up to 1 s).
- **The Mac reaches the phone while asleep only because "Wake for network access" is on** (`pmset` `womp 1`, usually only on the power adapter). Packets from the phone wake the Mac for a few seconds (`DarkWake … wifibt` in `pmset -g log`) and the connection comes back without lighting the screen. `wifibt` is the combined Wi-Fi and Bluetooth chip, so a Bluetooth mouse being moved shows up the same way: during the 16-minute sleep the Mac woke about once a minute while its mouse was being jostled on a bed.

**Mac on battery** — without wake for network access the sleeping Mac can't be reached. macOS still wakes it for a few seconds every 10 to 20 minutes for maintenance, and the phone sometimes connects then, but the connection is stuck once the Mac sleeps again: the phone, in light idle, never noticed (its read timeout didn't fire for 17 minutes), and a status it sent meanwhile stayed unacknowledged, so after the Mac woke the phone's `pong` waited behind TCP retransmissions spaced minutes apart. The Mac gave up after 60 s and the phone reconnected, 1 min 53 s after the wake. **Fix:** when macOS posts `NSWorkspace.didWakeNotification` (a real wake, not a dark wake), the Mac waits for the network to be back and closes the phone's connection, and the phone reconnects at once. A 21-minute sleep on battery then took 3 s from wake to battery in the menu.

**A night with the real app** — 2026-10-17 to 18, phone unplugged at 00:22 with 100%, screen off from about 01:19 to 08:32, Mac on the power adapter and asleep:

- **The connection held all night.** Debug builds of the Android app append each connection event (start, connect, close with the reason, retries, pings, network lost or blocked, shutdown) to `files/diagnostics.log`, with the phone's state at that moment (Doze, screen, network, battery); read it with `adb shell run-as com.julianamarques.galaxybridge cat files/diagnostics.log`. It shows a `ping` every 2 minutes, in Doze too, whenever the Mac was awake.
- **The Mac's Power Nap sets the rhythm.** On the power adapter the sleeping Mac spends long stretches in dark wake (1 to 1.5 hours each, as on nights before the app existed) and keeps pinging. When it really sleeps the pings stop, the phone's read timeout runs out 6 minutes later, and its reconnection wakes the Mac (`wifibt`), which accepts it. Seven such reconnections, each taking 2 s. These are the hourly reconnections of earlier nights; no "connection abort" this time.
- **The app's own battery cost is negligible:** 0.17 mAh for the whole night in `dumpsys batterystats`, against 1,277 mAh for the phone. The phone's total (747 mAh with the screen off, about 2.75% per hour) says nothing about the app: a USB-C to 3.5 mm adapter with wired earphones stayed plugged in all night, and its USB controller held the CPU awake for 6 hours (`Kernel Wake lock a600000.ssusb`). It isn't known whether something similar inflated the Phase 0 numbers.

Still open, to look at in Phase 2:

- **"Software caused connection abort" on the phone.** Twice during the 16-minute sleep test, not seen since, and each time the phone reconnected within a second. On Android this error means the system destroyed the app's socket. Ruled out by provoking them with the diagnostic log on: deep Doze (a whole night without it), battery saver (pings kept arriving), and Wi-Fi dropping for a second (the app closes the socket itself first, "Socket closed", and reconnects in 1 s). Left: the phone's IP address changing or Wi-Fi roaming to another access point or band, which make Android destroy the sockets of the old address. Monitored through the diagnostic log; low impact.
- **A crashed Mac app** still leaves the phone waiting its own 6 minutes, since nothing closes the connection. Measured with `kill -9` and an immediate relaunch: the phone came back after 4 min 10 s, when its read timeout ran out (6 minutes after the Mac's last ping). Rare enough to leave as is. The cause is that Network.framework runs TCP inside the app's process, so a killed app neither closes the connection nor answers the phone. Fixes considered and not taken: a shorter read timeout on the phone (small gain, and its timers run late in light idle), a UDP nudge from the relaunched Mac to the phone's last address (a new message and an open port on the phone), and kernel sockets with another TLS 1.3 library such as swift-nio-ssl (a rewrite of the server).
- **The phone's overall battery overnight** with nothing plugged into the USB port, for a realistic total.

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
