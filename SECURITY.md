# Security Policy

## Supported Versions

Galaxy Bridge is in development and has no published releases yet. Security fixes go to the main branch, for both the Mac app and the Android app.

| Version              | Supported |
| -------------------- | --------- |
| Main branch (0.1.x)  | Yes       |
| Earlier              | No        |

## Reporting a Vulnerability

Do not open a public issue to report vulnerabilities.

Use GitHub's private reporting: in the repository's **Security** tab, click **Report a vulnerability**. The report is visible only to the maintainer until a fix is published.

Whenever possible, include:

- A description of the problem and its impact.
- Steps to reproduce or a proof of concept.
- The Galaxy Bridge version on the Mac and on the phone, macOS version, phone model, Android and One UI versions.
- How the phone was connected: the Android app over Wi-Fi, the Android app over the USB cable, or adb.
- A suggested fix, if any.

## What to Expect

- Acknowledgment of the report within 7 days.
- An initial assessment and feedback on severity within 14 days.
- A fix in a new version, crediting the reporter if they wish.

Since the project is maintained by one person, these timelines may vary; the report will be followed through to the end.

## Scope

In scope:

- Pairing: the QR code and its secret, the certificates each side keeps and their pinning.
- The connection between the apps: the TLS server on the Mac, the phone's client, the USB accessory tunnel and the Bonjour discovery.
- Anything the Mac can make the phone do, and the other way around: calls, notification actions and replies, Do Not Disturb, file transfers, the file browser (paths outside the phone's shared storage must be refused), the gallery, the camera, links, the clipboard and screen mirroring control.
- The Android app's accessibility service and screen capture.
- The build scripts, including the checksum verification of downloaded components (`adb` and the scrcpy server).

Out of scope (report directly to the upstream projects):

- Vulnerabilities in the scrcpy server: [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy).
- Vulnerabilities in `adb`, Android or One UI: [Android Security](https://source.android.com/docs/security/overview/updates-resources).
- Attacks that require physical access to the unlocked Mac or the unlocked phone.
- The Gatekeeper warning on first launch, caused by the Mac app's local signature.

## Security Considerations for Users

- **Pairing.** The QR code shown on the Mac carries a one-time secret. Don't share a photo of it. After pairing, the phone talks only to that Mac and the Mac only to the phones paired with it, checked by certificate on every connection, also over the USB cable. **Settings › Esquecer Este Galaxy** on the Mac and **Esquecer este Mac** on the phone undo the pairing on both sides.
- **Local only.** Nothing goes through a server: the apps talk over the local network or the cable, encrypted with TLS 1.3. Calls, notifications (including their text and pictures), contacts you search for, photos, files and the clipboard reach the Mac, so pair only a Mac you trust and protect it with a password.
- **Permissions on the phone.** Notification access lets the app read every notification. All files access lets the Mac browse the phone's shared storage. The accessibility service (**Controle pelo Mac**) lets the paired Mac tap and type on the phone while the screen is mirrored. Turn off in Android's settings what you don't use.
- **Screen mirroring.** Android asks to confirm each time the screen is captured. While the mirror window is open, text copied on the Mac reaches the phone's clipboard; avoid copying passwords during that time if you don't want them on the phone.
- **adb mode.** Android's USB debugging and Wireless debugging give the paired computer full control of the phone, and `adb` does not check the phone's identity on wireless connections: another device on the same network could impersonate your Galaxy. Pair only Macs you trust, prefer the cable on public or shared networks, and revoke Macs you no longer use in **Developer options › Wireless debugging › Paired devices**. The Android app's own connection doesn't have this problem, since both sides check each other's certificate.
- **USB cable.** In accessory mode, any Mac running Galaxy Bridge can ask the phone to switch modes, but the connection inside the cable is the same TLS connection, and the phone accepts only the Mac it was paired with.
