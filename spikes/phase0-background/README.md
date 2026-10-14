# Phase 0 spike: staying alive in the background

Throwaway app for the second question of [the architecture plan](../../docs/architecture.md#phase-0--spikes-on-the-galaxy-s25):
does a `connectedDevice` foreground service survive a night with the screen off and the battery set to Unrestricted?

`HeartbeatService` mimics `BridgeService`: no wakelock, a timer every 60 seconds, and a TCP connection to the Wi-Fi router on each tick to check that the local network is still reachable. Each tick appends a row to `files/heartbeat.csv`, since logcat doesn't keep a whole night.

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell pm grant com.julianamarques.galaxybridge.spike.background android.permission.POST_NOTIFICATIONS
adb shell am start -n com.julianamarques.galaxybridge.spike.background/.MainActivity
# next morning
adb shell run-as com.julianamarques.galaxybridge.spike.background cat files/heartbeat.csv
```

The `intervalo_s` column shows how long Android held the timer back while the screen was off.
