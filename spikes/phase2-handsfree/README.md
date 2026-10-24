# Phase 2 spike: the Mac as a Bluetooth hands-free device

Can the Mac play a phone call's audio by acting as the phone's Bluetooth hands-free device, like a headset or a car kit, through `IOBluetoothHandsFreeDevice`?

```bash
./build.sh
open build/HandsFreeSpike.app
```

Pair the phone with the Mac over Bluetooth first. The window lists the paired devices, connects as hands-free, and has buttons to answer, hang up and move the audio. Everything it sees is also written to `~/Library/Logs/GalaxyBridgeHandsFreeSpike.log`.

The "Banda larga (mSBC)" toggle decides whether the Mac offers codec negotiation; the app asks for the microphone at launch.

Result on the Galaxy S25 and macOS 27 (2026-10-18): the hands-free connection and the call state work, the audio doesn't (`kIOReturnUnsupported`), with or without mSBC and with the microphone allowed. Details in [docs/architecture.md](../../docs/architecture.md#phase-2-results). Unpair the phone from the Mac afterwards.

Read-only framework inspection on macOS 27.0.1 build 26A434 (2026-10-19) found that the connected-state paths in `connectSCO` construct the unsupported error directly. `transferAudioToComputer` calls the same method. The [investigation](../../docs/call-audio-investigation.md) records the evidence, its limits, and the remaining app-only hypotheses.

To reproduce selector and constant observations without pairing, connecting, or accessing a microphone:

```bash
xcrun clang -Wall -Wextra -fobjc-arc -framework Foundation -framework IOBluetooth inspect-runtime.m -o /private/tmp/galaxy-hfp-runtime-inspector
/private/tmp/galaxy-hfp-runtime-inspector
```

The inspector deliberately refuses other OS builds and architectures: its method lengths were checked for this build only. It is a research utility, not part of the app.
