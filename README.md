# Galaxy Bridge

Use a Samsung Galaxy (or any Android 11+) together with your Mac over Wi-Fi.

Galaxy Bridge lives in the menu bar. It shows whether the Galaxy is connected and its battery level, and places calls on the phone from the Mac: type a number in the menu, or make the phone numbers in Safari, Contacts, Calendar and other apps (`tel:` links) ring through the Galaxy. With the Android app, incoming calls show on the Mac with the caller's name and photo, to answer or decline from there, the menu finds the phone's contacts by name as you type, and the phone's notifications show on the Mac, where you can reply to them.

There are two ways to connect:

- **The Galaxy Bridge app on the phone** (recommended). Pair once with a QR code; after that the phone reconnects on its own whenever both are on the same Wi-Fi, also after a restart, without Developer options.
- **adb**, with nothing installed on the phone: Wireless debugging or USB debugging, the same connection [Galaxy Mirror](https://github.com/julianamarques/galaxy-mirror) uses. A Galaxy already set up in Galaxy Mirror works here without pairing again.

Galaxy Mirror shows and controls the phone's screen, and Galaxy Bridge brings the phone's features to the Mac.

## Requirements

- macOS 14 or later
- A phone with Android 11+ on the same Wi-Fi network as the Mac
- For the Android app: battery usage set to **Unrestricted**, so Android doesn't cut its network while the screen is off, notification access, to read the caller's name from the dialer, and access to contacts, to search them from the Mac (the app asks for all three)
- For adb: Wireless debugging (or USB debugging and a cable) turned on

## Build

### Mac app

The Swift package in `macos/`:

```bash
cd macos
./scripts/build-app.sh          # builds build/Galaxy Bridge.app
./scripts/build-app.sh debug    # debug build
```

`swift test` (in `macos/`) runs the tests. The app icon is drawn in SwiftUI by `scripts/make-icon.swift`; run it after changing the drawing to regenerate `Resources/AppIcon.icns`. In debug builds, `GALAXY_PREVIEW_MENU=1` shows the menu in a regular window and `GALAXY_PREVIEW_SETTINGS=1` opens Settings at launch, to check the design without clicking the menu bar.

The build script copies the Swift package resources (PhoneNumberKit's phone number data) into the app and downloads `adb` (`scripts/fetch-adb.sh`, platform-tools 37.0.1) and checks its checksum. Keep this version the same as Galaxy Mirror's: two different `adb` versions restart each other's server and drop the connection.

### Android app

The Gradle project in `android/`. It needs a JDK 17 or later and the Android SDK (API 37), with the SDK's path in `android/local.properties` (`sdk.dir=…`, not committed):

```bash
cd android
./gradlew assembleDebug         # app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest     # protocol tests, against protocol/fixtures
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Install it with `adb` while developing. A plain APK opened on the phone is blocked by Play Protect in Brazil because of the permissions the app asks for, so users will get it from a store (see [Distribution](docs/architecture.md#distribution)).

To pair: on the Mac, **Settings › Usar o App no Galaxy…** shows a QR code. On the phone, open Galaxy Bridge, grant the permissions and scan the code.

## Structure

```
macos/                    the Mac app (Swift package)
├── Sources/
│   ├── BridgeProtocol/   messages, framing, TLS identity, pairing, BridgeServer (no UI)
│   ├── GalaxyKit/        adb connection, shared with Galaxy Mirror
│   └── GalaxyBridge/     the menu bar app
│       ├── App/          entry point and app delegate (tel: links)
│       ├── ViewModels/   AppModel (connection, battery, calls) and SetupModel (pairing)
│       ├── Services/     call panel, Notification Center (missed calls, phone notifications), phone apps and icons
│       ├── Views/        menu, call panel, setup flow, settings and components
│       └── Extensions/   default tel: handler, launch at login, links
├── Tests/                BridgeProtocolTests, GalaxyKitTests
├── Resources/            Info.plist, icon, bundled adb
└── scripts/              build, adb download, icon
android/                  the Android app (Kotlin, Jetpack Compose)
└── app/src/main/java/com/julianamarques/galaxybridge/
    ├── bridge/           BridgeService, TLS connection, Keystore identity, Mac discovery, calls, contacts, notification relay
    ├── protocol/         messages and framing
    └── ui/               onboarding and pairing screens
protocol/                 protocol reference and JSON fixtures shared by both test suites
docs/                     architecture, plans and test results
spikes/                   Phase 0 experiments (throwaway)
```

## How it works

- **Connection (Android app)** — the Mac listens on port 52800 and advertises `_galaxybridge._tcp` over Bonjour; the phone connects to it with TLS 1.3, both sides pinning the other's certificate from the QR code pairing. A foreground service on the phone reconnects when Wi-Fi comes back, after a restart and when the Mac app reopens. The Mac pings every 2 minutes to tell a phone that has gone from a quiet one. Details in [protocol/protocol.md](protocol/protocol.md) and [docs/architecture.md](docs/architecture.md).
- **Connection (adb)** — the same flow as Galaxy Mirror: pairing with a QR code or a six-digit code, `adb connect` to the phone's `_adb-tls-connect._tcp` service, switching to the USB cable when it is plugged in, and reconnecting every 30 seconds while the phone is away.
- **Battery** — the Android app sends it when it changes; with adb, `dumpsys battery` every minute.
- **Calls** — the Android app dials with `TelecomManager.placeCall()`; with adb, `am start -a android.intent.action.CALL`. Numbers are formatted as you type and dialed in international format (`+55 86 99999-0001`) with [PhoneNumberKit](https://github.com/PhoneNumberKit/PhoneNumberKit), using the country of the network the Galaxy is on (so it follows you when traveling), then the SIM's country, then the Mac's region. The audio stays on the phone (or on the earbuds connected to it). **Settings › Calls** makes the app the default handler for `tel:` links; macOS asks for confirmation.
- **Notifications (Android app)** — the phone's notifications show in the Mac's Notification Center under the sending app's name, with their buttons, including **Reply** with a text field. Dismissing one on either side dismisses it on the other. Ongoing, silent and call notifications stay on the phone, and **Settings › Notificações** turns off the apps you don't want on the Mac.
- **Contacts (Android app)** — typing a name in the menu searches the phone's contacts as you type (`contacts.search`); the contacts stay on the phone and the Mac only keeps the latest results and the photos it showed.
- **Incoming calls (Android app)** — the phone follows the call state and reads the caller's name and number from the dialer's notification. On the Mac a panel in the top-right corner shows the caller with Answer and Decline, then the call's duration with End; a call nobody answered, including one taken by One UI's direct voicemail, leaves a "Ligação perdida" notification.

## Roadmap

Features that work without an Apple Developer account:

- [x] Connection status and battery in the menu bar
- [x] Calls from the Mac
- [x] Android app, with no Developer options on the phone
- [x] Incoming calls on the Mac, with Answer and Decline
- [x] Phone notifications on the Mac, with replies
- [ ] "Send to Galaxy" in the Finder (Services menu)
- [ ] File browser and photo import

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
