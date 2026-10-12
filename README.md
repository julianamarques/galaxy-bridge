# Samsung for Mac

Use a Samsung Galaxy (or any Android 11+) together with your Mac — over Wi-Fi or a USB cable, with nothing to install on the phone.

Samsung for Mac lives in the menu bar. It shows whether the Galaxy is connected and its battery level, and places calls on the phone from the Mac: type a number in the menu, or make the phone numbers in Safari, Contacts, Calendar and other apps (`tel:` links) ring through the Galaxy.

It is the companion to [Galaxy Mirror](https://github.com/julianamarques/galaxy-mirror): Galaxy Mirror shows and controls the phone's screen, and Samsung for Mac brings the phone's features to the Mac. Both use the same `adb` server, so a Galaxy already set up in Galaxy Mirror can be used here without pairing again.

## Requirements

- macOS 14 or later
- A phone with Android 11+ on the same Wi-Fi network as the Mac (or connected with a USB cable), with Wireless debugging (or USB debugging) turned on

## Build

```bash
./scripts/build-app.sh          # builds build/Samsung for Mac.app
./scripts/build-app.sh debug    # debug build
```

`swift test` runs the tests.

The build script copies the Swift package resources (PhoneNumberKit's phone number data) into the app and downloads `adb` (`scripts/fetch-adb.sh`, platform-tools 37.0.1) and checks its checksum. Keep this version the same as Galaxy Mirror's: two different `adb` versions restart each other's server and drop the connection.

## Structure

```
Sources/
├── GalaxyKit/        connection to the phone, shared with Galaxy Mirror (adb, Bonjour, pairing, device models)
└── SamsungForMac/    the menu bar app
    ├── App/          entry point and app delegate (tel: links)
    ├── ViewModels/   AppModel (connection, battery, calls) and SetupModel (pairing)
    ├── Views/        menu, setup flow, settings and components
    └── Extensions/   default tel: handler, launch at login, links
Tests/GalaxyKitTests/
```

## How it works

- **Connection** — the same flow as Galaxy Mirror: pairing with a QR code or a six-digit code, `adb connect` to the phone's `_adb-tls-connect._tcp` service, switching to the USB cable when it is plugged in, and reconnecting every 30 seconds while the phone is away.
- **Battery** — `dumpsys battery`, read every minute while connected.
- **Calls** — `am start -a android.intent.action.CALL`. Numbers are formatted as you type and dialed in international format (`+55 86 99999-0001`) with [PhoneNumberKit](https://github.com/PhoneNumberKit/PhoneNumberKit), using the country of the network the Galaxy is on (so it follows you when traveling), then the SIM's country, then the Mac's region. The audio stays on the phone (or on the earbuds connected to it). **Settings › Calls** makes the app the default handler for `tel:` links; macOS asks for confirmation.

## Roadmap

Features that work without an Apple Developer account:

- [x] Connection status and battery in the menu bar
- [x] Calls from the Mac
- [ ] Phone notifications on the Mac
- [ ] "Send to Galaxy" in the Finder (Services menu)
- [ ] File browser and photo import

## License

Apache 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
