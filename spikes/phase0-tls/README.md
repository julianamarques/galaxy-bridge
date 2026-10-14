# Phase 0 spike: mutual TLS with pinned certificates

Throwaway code for the third question of [the architecture plan](../../docs/architecture.md#phase-0--spikes-on-the-galaxy-s25):
can an Android Keystore key be the client certificate in a TLS 1.3 connection to `NWListener`, with both sides pinning?

- `mac/` — `TLSSpikeServer`: a self-signed P-256 identity generated with swift-certificates and kept in files (`identity/`, git-ignored), turned into a `SecIdentity` in memory with `SecIdentityCreate` (no Keychain). It requires a client certificate and checks its SHA-256 fingerprint.
- `android/` — a P-256 key in the Android Keystore with the self-signed certificate Keystore generates; a key manager that offers it as the client certificate and a trust manager that only accepts the pinned Mac.

```bash
cd android && ./gradlew assembleDebug && adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am broadcast -n com.julianamarques.galaxybridge.spike.tls/.CommandReceiver -a com.julianamarques.galaxybridge.spike.tls.INIT   # logs the phone's fingerprint
cd ../mac && swift run TLSSpikeServer --pin <phone fingerprint>                                                                       # logs the Mac's fingerprint
adb reverse tcp:52800 tcp:52800
adb shell am broadcast -n com.julianamarques.galaxybridge.spike.tls/.CommandReceiver -a com.julianamarques.galaxybridge.spike.tls.CONNECT --es pin <Mac fingerprint>
adb logcat -s GBSpike
```
