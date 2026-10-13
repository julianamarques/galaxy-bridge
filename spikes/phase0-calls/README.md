# Phase 0 spike: calls

Throwaway app that answers the first question of [the architecture plan](../../docs/architecture.md#phase-0--spikes-on-the-galaxy-s25):
can a third-party app answer and decline calls on One UI, and what does it learn about the caller?

Pick a method, then call the phone from another one. When it rings, the app waits 3 seconds, runs the method and logs everything under the `GBSpike` tag.

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
./grant.sh                                   # runtime permissions and notification access, through adb
./mode.sh sequence                           # one method per call, in order; or a single one: answer_telecom, decline_telecom, answer_notification, decline_notification, observe
adb logcat -s GBSpike
```

After answering, the app ends the call 5 seconds later with the matching method (`endCall()` or the notification's hang-up action).

The command receiver only accepts broadcasts from adb (it requires the `DUMP` permission, which only the shell and the system hold). Uninstall the app when done: `adb uninstall com.julianamarques.galaxybridge.spike`.
