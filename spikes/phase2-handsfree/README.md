# Phase 2 spike: the Mac as a Bluetooth hands-free device

Can the Mac play a phone call's audio by acting as the phone's Bluetooth hands-free device, like a headset or a car kit, through `IOBluetoothHandsFreeDevice`?

```bash
./build.sh
open build/HandsFreeSpike.app
```

Pair the phone with the Mac over Bluetooth first. The window lists the paired devices, connects as hands-free, and has buttons to answer, hang up and move the audio. Everything it sees is also written to `~/Library/Logs/GalaxyBridgeHandsFreeSpike.log`.

The "Banda larga (mSBC)" toggle decides whether the Mac offers codec negotiation; the app asks for the microphone at launch.

Result on the Galaxy S25 and macOS 27 (2026-10-18): the hands-free connection and the call state work, the audio doesn't (`kIOReturnUnsupported`), with or without mSBC and with the microphone allowed. Details in [docs/architecture.md](../../docs/architecture.md#phase-2-results). Unpair the phone from the Mac afterwards.
