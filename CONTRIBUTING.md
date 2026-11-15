# How to Contribute

Thank you for your interest in contributing to Galaxy Bridge. This guide describes the recommended workflow for proposing fixes, improvements and documentation changes.

The project has two apps that talk to each other: the Mac app (Swift package in `macos/`) and the Android app (Gradle project in `android/`). The messages between them are described in [protocol/protocol.md](protocol/protocol.md) and the design decisions in [docs/architecture.md](docs/architecture.md).

## Workflow

- Fork the repository and clone the project.
- Create a branch from the main branch.
- Use descriptive branch names, such as `feature/feature-name` or `fix/short-description`.
- See `README.md` to build and run both apps locally.
- Keep pull requests small and focused on one main change.
- In the pull request, explain the problem solved, the solution applied and how the change was validated.

## Commits

Write messages in English, short, in the imperative mood and with a prefix that indicates the type of change ([Conventional Commits](https://www.conventionalcommits.org/)), with a scope when the change touches only one app:

```text
feat: open links from the phone on the Mac
fix(mac): keep the mirror window inside the screen on rotation
fix(android): send the app list in batches
refactor: move the USB framing into AccessoryLink
test: cover the gallery request fixtures
docs: explain the USB cable mode
build: bump the bundled scrcpy server
```

## Code Standards

Both apps:

- Do not add comments to the code: prefer clear names, small functions and explicit types. Only scripts keep comments.
- Keep one type per file, named after the type.
- Logic that does not depend on the UI or on a device (parsing, the protocol, framing, size calculations) should live in pure functions, with tests.
- Do not commit the binaries downloaded by the scripts (`macos/Resources/adb`, `macos/Resources/scrcpy-server`), signing keys, `android/local.properties`, credentials or personal data.

Protocol:

- A new message or field goes in both apps in the same change: `macos/Sources/BridgeProtocol/Message.swift` and `android/.../protocol/Protocol.kt`.
- Add an example to `protocol/fixtures` (the file name starts with the message type followed by a dot) and describe it in `protocol/protocol.md`. Both test suites round-trip every fixture.
- New fields are optional, so an older app on the other side keeps working.

Mac app:

- Follow the existing organization in `App`, `Mirror`, `ViewModels`, `Services`, `Views` and `Extensions`; extensions go in `Extensions/` in the `Type+Topic.swift` format.
- The package uses the Swift 6 language mode, with strict concurrency checking. Do not introduce compiler warnings.
- User-facing strings are written in Brazilian Portuguese in the code (`String(localized:)`, `Text("…")`) and translated in `macos/Resources/en.lproj/Localizable.strings`. After changing any text, run `./scripts/check-translations.sh`: it must report no missing and no unused strings.
- When updating the scrcpy server, change the version and the checksum in `scripts/fetch-scrcpy.sh` together with `ScrcpyProtocol.serverVersion`, and review the protocol (the format may change between versions).

Android app:

- Kotlin and Jetpack Compose with Material 3 Expressive, following the existing `bridge`, `mirror`, `protocol` and `ui` packages.
- Texts shown to the user live in `res/values/strings.xml` (English) and `res/values-pt/strings.xml` (Brazilian Portuguese), never in the code. Escape apostrophes (`\'`).
- A feature that needs a permission declares it in `Permissions.kt`, shows it in the introduction (`ui/Onboarding.kt`) and on the home screen tiles.

## Validation

Before opening a pull request, run the applicable checks:

```sh
cd macos
swift build
swift test
./scripts/check-translations.sh
./scripts/build-app.sh

cd ../android
./gradlew assembleDebug testDebugUnitTest
```

Also check that:

- The change is limited to the proposed scope.
- The builds have no warnings and all tests pass.
- New rules have tests when applicable.
- New strings show up correctly in Portuguese and in English, on both apps.
- Both apps were tested together with a real phone when the change affects the connection, calls, notifications, transfers or mirroring (Wi-Fi and USB cable, when possible).
- No credentials, tokens or personal data were committed.
- The documentation (`README.md`, `protocol/protocol.md`, `docs/architecture.md`) was updated when the change affects how the project is used or how the apps talk to each other.

## Pull Requests

When opening a pull request, include:

- A short summary of the change.
- The reason for the change.
- The commands run for validation.
- The phone, Android and One UI versions, macOS version and type of connection used in manual testing.
- Notes on compatibility impacts, if any, such as a protocol change that needs both apps updated.

## Issues

When opening an issue, include:

- A clear description of the problem or improvement.
- Steps to reproduce, for a bug.
- Expected behavior and current behavior.
- The Galaxy Bridge version on both sides, phone model, Android and One UI versions, macOS version and whether the Mac is Apple Silicon or Intel.
- How the phone is connected: the Android app over Wi-Fi, the Android app over the USB cable, or adb.
- Relevant logs. On the Mac:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "com.julianamarques.GalaxyBridge"' --info
```

On the phone, debug builds keep a connection log that can be read with:

```sh
adb shell run-as com.julianamarques.galaxybridge cat files/diagnostics.log
```

Remove phone numbers, names and other personal data from logs before sharing them.
