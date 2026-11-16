# Call audio investigation

Investigated 2026-10-19. Scope: normal carrier/SIM calls, Galaxy S25 and the existing Mac, installed companion apps, no USB or wireless debugging and no additional hardware. Listening on the Mac is the first goal; sending the Mac microphone into a call is a separate requirement.

**No end-to-end solution has been validated under these constraints.** There is stronger evidence for why the existing Bluetooth spike fails, and three remaining experiments with distinct limitations. Do not ship a call-audio toggle based on these hypotheses.

## What the local Bluetooth implementation actually does

The earlier live spike established that HFP call control works, but opening its SCO audio connection reports `kIOReturnUnsupported` (`0xe00002c7`). Both CVSD and mSBC were tried with microphone access granted.

On **macOS 27.0.1, build 26A434, arm64**, read-only inspection of the loaded IOBluetooth framework found:

- `-[IOBluetoothHandsFreeDevice transferAudioToComputer]` branches directly to the Objective-C `connectSCO` selector. These are not independent ways to open audio.
- `-[IOBluetoothHandsFree connectSCO]` checks `isSCOConnected`, sets the device's codec type, then checks `codecID` and `handsFreeState`.
- For state `2`, both the codec-ID-`2` branch and the other-codec branch construct the literal `0xe00002c7`. The shared callback path passes that error to the delegate. The error is constructed in this method; it is not the return value of an attempted SCO-open call in these branches.
- If the service-level connection is not ready, the method sets `connectSCOAfterSLCConnected` and calls `connect`. The already-SCO-connected branch reports a different status; it does not establish a new channel.

Useful offsets relative to `connectSCO` in this exact build:

| Offset | Observation |
| --- | --- |
| `0x170` | `isSCOConnected` selector call |
| `0x2c0`, `0x2ec` | `codecID` selector calls |
| `0x2dc` | `setCodecType:` selector call |
| `0x2f8` | `handsFreeState` selector call |
| `0x300`, `0x308`, `0x45c` | Compare codec/state to `2` |
| `0x3c4`, `0x518`, `0x5a8` | Load `0xe00002c7` using a pair of instructions |
| `0x5cc` | `performSelector:withObject:withObject:` callback |
| `0x654`, `0x65c` | `setConnectSCOAfterSLCConnected:`, then `connect` |

The inspection uses Objective-C runtime metadata and reads the method implementation; it never constructs a Bluetooth device or calls a Bluetooth operation. The companion [runtime inspector](../spikes/phase2-handsfree/inspect-runtime.m) reproduces the selector/constant observations on this build. No Apple binaries are committed.

**Rechecked 2026-11-16 on macOS 27.2.1, build 26B131:** `connectSCO` is unchanged, still building `0xe00002c7` in the connected state without opening a channel, and `transferAudioToComputer` still calls it. No IOBluetooth code path reaches the SCO-connected state. `bluetoothd` declines an SCO request from the remote side ("SCO connect-accept declined") unless its own audio code expects that device, so a call the phone tries to route to the Mac is refused too. Other 2026 projects report the same result with other phones on macOS 26 and 27: [PhoneBridge](https://github.com/hari157/PhoneBridge), [Pickup](https://github.com/macx/pickup), [kaaka](https://github.com/twilighty-abhi/kaaka/pull/2).

**Implication:** further codec or microphone-permission changes are not a promising fix for this particular API/build. This does **not** establish that the hardware cannot carry SCO, that every macOS version behaves identically, or that no private daemon/driver path exists. No working alternative native path was found. Merely patching away an error would not implement the missing audio transport.

The old raw-HCI workaround also has a concrete blocker on this build: exported functions `BluetoothHCIRequestCreate`, `BluetoothHCISendRawCommand`, `BluetoothHCISendRawACLData` and `BluetoothHCIRequestDelete` are two-instruction stubs (`mov w0, #0; ret`). `BluetoothHCISendRawSCOData` was not exported. This was checked by reading their addresses, without executing any HCI request. InternalBlue's macOS implementation depends on the first two functions, so its historical support does not demonstrate a functioning path here. [InternalBlue implementation](https://github.com/seemoo-lab/internalblue/blob/master/macos/IOBluetoothExtended/IOBluetoothExtended/HCICommunicator.m)

## 1. Samsung Call and Message Continuity (CMC)

This is a real call-audio mechanism to investigate. Samsung documents calls on supported Galaxy tablets/PCs/watches with the same Samsung account and an activated SIM in the primary phone. Its supported-device list does not include a Mac. [Samsung documentation](https://www.samsung.com/us/mobile/connected-experience/)

A research experiment demonstrates CMC calls between a Galaxy Flip5 and Tab S9 FE using Wi-Fi/operator networks. It corroborates the mechanism, but does not publish a complete interoperable client implementation. [Original paper](https://di0zxmb8pwajl.cloudfront.net/kiisc/conference/mobisec2024/5A-4.pdf)

**Implementation clue, not a public API contract:** inspection of publicly available decompiled Samsung implementation code (`CmcAccountManager.java`) shows an IMS profile populated with a Samsung account access token, device identity, primary-device identity, line identity, P-CSCF addresses, activation state and per-secondary-device calling permission. The code also has a same-Wi-Fi/P2P mode. [Inspected implementation](https://github.com/488315/samsung_framework/blob/main/imsservice/sources/com/sec/internal/ims/core/cmc/CmcAccountManager.java)

The resulting hypothesis is that a Mac could act as an authorized CMC secondary device. The unresolved prerequisite is **supported enrollment and provisioning of that client**. Implementing SIP/RTP alone does not solve it. The existing Android companion has not been shown to have access to these privileged services or their credentials. The presence of a same-Wi-Fi mode does not establish a way to omit account enrollment.

First useful milestone: establish how a user-authorized secondary client obtains its own identity and calling authorization, then prove a registration succeeds. Only after that should we build the audio pipeline. Samsung account/server requirements may also conflict with Galaxy Bridge's current local-only/no-account goal.

### Samsung Phone in a Windows VM as a CMC experiment

There is a separate [SamsungPhone Windows application](https://apps.microsoft.com/detail/9mwjxxlchbgk?gl=US&hl=en-US). Samsung's CMC support team explicitly handles its diagnostics. [Samsung CMC team's response](https://r1.community.samsung.com/t5/pc/pc-%EC%82%BC%EC%84%B1-%EC%A0%84%ED%99%94-%EA%B4%80%EB%A0%A8-%EC%B6%94%EA%B0%80-%EB%AC%B8%EC%9D%98/m-p/25457638)

A first-hand test reports incoming/outgoing calls over Wi-Fi between a Flip6 and Galaxy Book5 Pro. The author's separate non-Samsung-PC test labels Samsung Phone usable but requiring an Intel CPU. Those are historical user observations, not current official architecture requirements or proof of Mac VM compatibility. [Call test](https://www.reddit.com/r/samsung/comments/1h1zl6n/my_experience_with_the_samsung_phone_and_laptop/), [PC compatibility test](https://www.reddit.com/r/GalaxyBook/comments/1h4xlk0/microsoft_store_links_for_samsung_pc_apps/)

This suggests a potentially cheaper CMC proof than implementing a new client: run the existing Samsung application in Windows, authenticate normally and test the Wi-Fi call path. Windows ARM packaging, runtime/device checks, required services and successful CMC registration in a Mac VM remain to be verified. Installing or launching the app alone is not proof. UTM 4.7.5 is already installed on this Mac; an existing Windows guest has not been confirmed. No guest was started or installed during this investigation.

A newer external package index lists a bundle identifier ending in `X64-Arm64`. This is a lead to verify in the official catalog/MSIX manifest, not confirmation of ARM support; the official metadata request was not completed. The historical Intel-only observation must not be used as a definitive current requirement. Even a confirmed ARM64 binary would not prove CMC authentication or audio works inside a VM. [Unverified packaging lead](https://dbox.tools/store/products/9MWJXXLCHBGK/0010/)

This experiment concerns the Samsung CMC application. Microsoft Phone Link's Bluetooth call path is a different mechanism and would retain the internal-controller access problem.

## 2. Accessibility microphone capture and acoustic relay

Android documents that an accessibility service can receive microphone input during a voice call. Capturing the call's digital uplink/downlink requires the separate privileged `CAPTURE_AUDIO_OUTPUT` permission. [Android audio-input sharing rules](https://developer.android.com/media/platform/sharing-audio-input#voice_call_ordinary_app)

There is a concrete implementation precedent: ACR Phone Helper's accessibility mode records through the microphone/loudspeaker on Android 10+, while its direct two-way mode uses Shizuku or root. Its developer also documents device-specific silence and headset limitations. [Developer's compatibility table](https://acr.app/)

Possible experiment: phone call on speaker → phone microphone captured by an explicitly enabled accessibility component → encrypted local stream → Mac playback. This could satisfy listening in some conditions, but is **not validated on this S25**. Echo cancellation may remove the other person's voice, capture may be silenced, and the phone must remain audible. It does not provide digital injection of the Mac microphone into the carrier call.

First useful milestone: during a controlled call, measure `AudioRecordingConfiguration.isClientSilenced()` and verify intelligible remote speech reaches the app's microphone capture. Stop this branch if it cannot. Avoid building the networking/player before this proof.

## 3. Read Samsung's native recording while it is being written

Samsung documents native call recording and saved recordings on supported configurations. This establishes a privileged recording path exists on those configurations, not that another app can stream it live. [Samsung recording documentation](https://www.samsung.com/jp/support/mobile-devices/how-do-i-record-a-call-and-how-do-i-check-my-recorded-voice-of-galaxy/)

Hypothesis: the user starts a native recording, grants Galaxy Bridge access to its recording folder, and the app reads newly written audio for playback on the Mac. This is a **low-confidence experiment**, not a working workaround.

Three independent gates must pass:

1. The exact phone/region exposes native call recording.
2. An ordinary app can open the in-progress file through user-granted storage access, and the bytes become available before hang-up.
3. The in-progress container exposes enough information for incremental audio decoding at useful latency.

Android explicitly rejects other apps opening a MediaStore item while its owner marks it `IS_PENDING`. Whether Samsung uses that flag, a private temporary file, or another layout on this build has not been measured. A finalized `.m4a` being readable after the call proves none of the live-streaming gates. [MediaStore contract](https://developer.android.com/reference/android/provider/MediaStore.MediaColumns#IS_PENDING)

This would support listening only; it does not provide a path for the Mac microphone. No recording or private recording-file inspection was performed during this investigation.

## Paths that do not currently meet the requirements

| Path | Reason |
| --- | --- |
| scrcpy voice-call capture, Shizuku, embedded/local ADB | Still depends on debugging or root; moving ADB into an app does not remove the dependency. [Example: JemRec's documented setup](https://github.com/jemcik/JemRec) |
| Default dialer / `InCallService` | Controls calls and selects existing audio endpoints; does not grant raw carrier-call PCM or define a new Wi-Fi audio endpoint. [Endpoint API](https://developer.android.com/reference/android/telecom/InCallService#requestCallEndpointChange(android.telecom.CallEndpoint,%20java.util.concurrent.Executor,%20android.os.OutcomeReceiver%3Cjava.lang.Void,%20android.telecom.CallEndpointException%3E)) |
| Android system call streaming | The AOSP system streaming role is system-only; installing an ordinary companion app is insufficient. [Role definition](https://android.googlesource.com/platform/packages/modules/Permission/+/refs/heads/main/PermissionController/res/xml/roles.xml) |
| ESP32, Raspberry Pi, USB Bluetooth bridge | Concrete HFP bridge implementations exist, but require extra hardware excluded by the user. |
| Bluetooth in a Windows/Linux VM | No demonstrated access to this Mac's internal controller for the required HFP audio role; a VM alone does not establish that capability. |
| Carrier forwarding / a separate VoIP number | Changes the call route/service rather than relaying this existing SIM call locally; not an implementation of the requested integration. |

## Decision

Prioritize checking the existing SamsungPhone application's current architecture/dependencies and, if compatible, its CMC registration in a Windows guest. This can test the protocol route before investing in a native client. Treat native CMC integration as protocol research with enrollment as its first gate. Treat accessibility as an acoustic fallback and native-recording streaming as a file-access experiment, each requiring an on-device proof before integration. Keep all three distinct from a validated, full-duplex call-audio feature.
