# Google Play declarations

Answers for the Play Console forms, in English for the reviewers. Every declaration asks for a demo video: record them on the phone with the Mac app beside it, show the feature working and the permission being granted, and upload them to YouTube as unlisted.

## Data safety

Galaxy Bridge never sends data to the developer or to the internet; it sends it to the user's own Mac. Google defines collection as data leaving the device, so the answers below declare it, the conservative choice: declaring more than needed isn't penalized, declaring less is.

- **Does your app collect or share any of the required user data types?** Yes
- **Is all of the user data collected by your app encrypted in transit?** Yes (TLS 1.3 with mutual certificate pinning)
- **Do you provide a way for users to request that their data be deleted?** No. The developer holds no user data; Forget on either device removes the pairing, and uninstalling removes everything stored on the phone.

For every type below: **collected: yes**, **shared: no**, **processed ephemerally: no** (unless noted), **required: optional** (the user can turn the feature off), **purpose: App functionality**.

| Category | Data type | Feature |
|---|---|---|
| Personal info | Name | Caller name and contact search results |
| Personal info | Phone number | Caller number, recent calls, contact search results |
| Messages | Other in-app messages | Notification content and quick replies |
| Photos and videos | Photos, Videos | Gallery browsing and photos sent to the Mac |
| Audio | Other audio files | Phone sound while mirroring (**processed ephemerally: yes**) |
| Files and docs | Files and docs | File browser and transfers |
| Contacts | Contacts | Contact search and caller identification |
| App activity | Installed apps | The app name of each notification and of the media playing |
| App activity | Other actions | Call history (recent calls) |
| Device or other IDs | Device or other IDs | The phone's name, model and pairing certificate |

## Call log (READ_CALL_LOG) — Permissions Declaration Form

- **Core functionality:** Galaxy Bridge connects an Android phone to the user's own Mac, so they can handle calls from the computer: see who is calling, answer, decline and place calls, and see recent calls.
- **Exception requested:** Cross-device synchronization or transfer of calls (connected device companion app).
- **Why the permission is needed:** the Mac's menu shows the phone's last 4 calls (number, contact name, type and time), the same list the phone's dialer shows, so the user can call back from the Mac. After an unanswered incoming call, the app reads the newest call log entry to tell a call the user declined from a missed one, so the Mac shows the right notification. The data goes only to the user's paired Mac over an encrypted local connection; it is never sent to the developer or any server.
- **Alternatives considered:** there is no other API for call history. The call state API (`TelephonyCallback`) doesn't say whether an ended call was missed or declined.

## All files access (MANAGE_EXTERNAL_STORAGE) — Permissions Declaration Form

- **Core functionality / permitted use:** file management. The Mac app includes a file browser for the phone's shared storage: the user browses any folder, downloads files to the Mac and uploads files from the Mac into the folder they choose.
- **Why the Storage Access Framework or MediaStore isn't enough:** the user browses the whole storage tree from the Mac, where Android's folder picker can't be shown, and the files include documents, archives and APKs, not only media. MediaStore only covers media and the app's own files.
- **Optional:** the permission is asked only when the user turns on the file browser; every other feature works without it.

## Photos and videos (READ_MEDIA_IMAGES, READ_MEDIA_VIDEO) — Photo and video permissions declaration

- **Core use:** the Mac app has a photo library window that shows every photo and video on the phone, grouped by month and album, with paging through the whole library; the user picks what to copy to the Mac.
- **Why the photo picker isn't enough:** the user browses the library from the Mac, so there is no picker on the phone to open, and the window needs access to the whole library, not a selection made in advance.

## Accessibility API — Accessibility declaration

- `isAccessibilityTool` is **not** set; the app shows the prominent disclosure (the screen mirroring step of the introduction) and asks for consent before sending the user to the accessibility settings.
- **What the service does:** during screen mirroring, which the user starts and confirms each time, it performs on the phone the taps, swipes, scrolls, key presses and text the user makes with the Mac's mouse and keyboard (`dispatchGesture`, the Back, Home, Recents and Notifications global actions, and `ACTION_SET_TEXT` and `ACTION_IME_ENTER` on the focused input field). When the user presses Copy or Cut on the Mac, it reads the text selected in the focused field and sends it to the Mac's clipboard (`ACTION_COPY` / `ACTION_CUT`).
- **What it doesn't do:** it doesn't read, store or send the rest of the screen's content; it ignores accessibility events, and it looks only at the focused text field. It does nothing when mirroring isn't running.
- **Why another API isn't enough:** Android offers no other way for an app to inject input into other apps.

## Foreground services

| Type | Service | Use | User impact if deferred |
|---|---|---|---|
| `connectedDevice` | `BridgeService` | Keeps the encrypted connection to the paired Mac (Wi-Fi or USB accessory) so calls, notifications and status reach the Mac while the phone is idle | Incoming calls and notifications would stop showing on the Mac |
| `mediaProjection` | `ScreenMirrorService` | Screen mirroring to the Mac, started by the user and confirmed in Android's dialog each time | Mirroring would stop |
| `microphone` | `ScreenMirrorService` | Captures the sound other apps play (`AudioPlaybackCapture`, which needs `RECORD_AUDIO`) so it plays on the Mac while mirroring. The microphone itself is never recorded | Mirroring would lose its sound |

## Battery optimization (REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)

No form, but reviewers check it. Use case: companion app for a connected device (the user's Mac) that must receive incoming calls and notifications in real time; without the exemption One UI puts the app to sleep and the Mac stops getting calls. The introduction explains this and the user grants it in Android's own dialog.

## App access (for the reviewers)

The app needs the Galaxy Bridge app for macOS to do anything beyond its introduction. In **App access**, choose "All or some functionality is restricted" and add one instruction with this text, plus the link to the demo video of the whole flow, since the reviewers may not have a Mac:

```
Galaxy Bridge is a companion app: it connects the phone to the Galaxy Bridge app for macOS. No account or login is needed.

1. On a Mac with macOS 14 or later, download and open https://github.com/julianamarques/galaxy-bridge/releases/latest/download/Galaxy-Bridge.dmg and drag Galaxy Bridge to Applications. The app is not notarized: on first launch, allow it in System Settings > Privacy & Security > Open Anyway.
2. Open Galaxy Bridge on the Mac and click Continue. It shows a QR code.
3. With the phone on the same Wi-Fi network as the Mac (or connected to it with a USB cable), open Galaxy Bridge on the phone, tap "Scan the Mac's code" and point the camera at the QR code.
4. The introduction then asks for the permission of each feature. Incoming calls, notifications, photos, files and screen mirroring then show up on the Mac.

Demo video of the whole flow: <link>
```

Privacy policy URL: https://github.com/julianamarques/galaxy-bridge/wiki/Privacy-Policy
