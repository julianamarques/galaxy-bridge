# Galaxy Bridge protocol

Version **1**. How the Mac app and the Android app talk to each other. The design and the reasons behind it are in [docs/architecture.md](../docs/architecture.md).

## Connection

- The **Mac listens** on TCP port 52800 (or any free port if that one is taken) and advertises the Bonjour service `_galaxybridge._tcp`. Its TXT record has `v` (protocol version) and `id` (the first 16 hex digits of the Mac's certificate fingerprint).
- The **phone connects**: first to the last address that worked, then to whatever Bonjour finds with the paired Mac's `id`.
- **TLS 1.3 only**, with a client certificate. Both certificates are self-signed P-256 certificates. Each side checks the other's **fingerprint** (the SHA-256 of the DER certificate, as 64 lowercase hex digits) instead of a certificate authority.
- The Mac accepts an unknown phone certificate only while it is showing a pairing code.

## Framing

Each message is a 4-byte big-endian length, then that many bytes of UTF-8 JSON. Messages are capped at 1 MiB; a bigger length closes the connection.

```json
{ "type": "call.place", "id": "c7a2", "body": { "number": "+5586999990001" } }
```

| Field | |
|---|---|
| `type` | The message type. Unknown types are ignored, so either app can be updated first. |
| `id` | Optional. Set on requests that can fail, so the answer can refer to it. |
| `replyTo` | Optional. The `id` of the request this message answers. |
| `body` | The message's fields. Left out when the message has none. Unknown fields are ignored. |

## Session

1. TLS handshake.
2. The phone sends `hello`.
3. **Paired phone:** the Mac answers `hello`. **New phone** (only while pairing): the phone sends `pair.request`, the Mac answers `pair.accepted` and then `hello`, or `pair.rejected` and closes.
4. The phone treats the connection as established only when the Mac's `hello` arrives. In TLS 1.3 its handshake can succeed even when the Mac is about to reject its certificate.
5. The phone sends `status` right away and again whenever it changes.

If the major version in `hello` differs, the Mac sends `error` with code `version` and closes.

**Keep-alive:** the Mac sends `ping` every 2 minutes, whatever else the phone is sending, and the phone answers `pong`. If nothing arrives within 60 seconds of the `ping`, the Mac closes the connection. The phone closes it after 6 minutes without any message and reconnects. When the phone shuts down or restarts, or the Mac app quits, that side closes the connection first, so the other notices at once.

## Messages

### `hello` — both directions

```json
{ "type": "hello", "body": { "version": 1, "appVersion": "0.1.0", "name": "Galaxy S25", "model": "SM-S931B" } }
```

`name` is the name the user gave the device. `model` is the hardware model.

### `pair.request` — phone → Mac

```json
{ "type": "pair.request", "body": { "secret": "q3HcKk0b5mJ8b1yZ1Xr7Ag", "name": "Galaxy S25", "model": "SM-S931B" } }
```

`secret` is the token from the QR code, or the six-digit code the user typed. The Mac accepts it once, for 2 minutes. Five wrong six-digit codes cancel the pairing.

### `pair.accepted` — Mac → phone

```json
{ "type": "pair.accepted", "body": { "name": "MacBook Air" } }
```

### `pair.rejected` — Mac → phone

```json
{ "type": "pair.rejected", "body": { "reason": "expired" } }
```

`reason`: `expired` (no pairing in progress, or the code timed out) or `invalid` (wrong secret).

### `unpair` — both directions

```json
{ "type": "unpair" }
```

Sent when the user forgets the other device. The receiver forgets the sender too and closes the connection.

### `status` — phone → Mac

```json
{ "type": "status", "body": { "battery": { "level": 71, "charging": false }, "networkCountry": "BR", "simCountry": "BR" } }
```

Countries are ISO 3166-1 alpha-2 codes in uppercase, left out when unknown (no signal, no SIM). The Mac uses them to format and dial numbers.

### `call.place` — Mac → phone

```json
{ "type": "call.place", "id": "c7a2", "body": { "number": "+5586999990001" } }
```

`number` is already in E.164. The phone places the call and answers only if it fails, with `error`.

### `call.state` — phone → Mac

```json
{ "type": "call.state", "body": { "call": "7", "state": "ringing", "direction": "incoming", "number": "+5586999990001", "name": "Maria" } }
```

Sent on every change of the phone's call, and once after `hello` if a call is already under way. `call` identifies the call; the phone picks it, and it stays the same until the call ends.

| `state` | |
|---|---|
| `ringing` | An incoming call is ringing. |
| `active` | The call was answered, or an outgoing call was placed. Android doesn't tell dialing from connected. |
| `voicemail` | One UI's direct voicemail picked up an unanswered call. The Mac treats it as unanswered. |
| `ended` | The call is over. The phone forgets it. |

`declined` is `true` on the `ended` of an unanswered incoming call that was declined, on the phone or from the Mac, so the Mac doesn't show it as missed. The phone reads it from its call history, which takes up to 3 s after the call ends and needs the call log permission; without it, `declined` is left out and the call counts as missed.

`direction` is `incoming` or `outgoing`. `name` is the contact name and `number` the number, both as the dialer shows them (the number is often national, like `086…`), left out until known. They usually arrive in a second `call.state` a moment after the first. `contact` is the phone's contact ID when the number is in the phone's contacts, so the Mac can ask for the photo; for calls placed with `call.place`, the phone fills in the number it dialed and its contact.

### `call.answer` / `call.decline` / `call.end` — Mac → phone

```json
{ "type": "call.answer", "id": "a1", "body": { "call": "7" } }
```

Answer or decline the ringing call, or hang up the call. Ignored when `call` is not the phone's current call. The new state arrives as `call.state`; the phone answers with `error` only if it can't (`permission` when it lacks the phone permissions).

### `contacts.search` / `contacts.results` — Mac → phone / phone → Mac

```json
{ "type": "contacts.search", "id": "s3", "body": { "query": "pai", "limit": 8 } }
{ "type": "contacts.results", "replyTo": "s3", "body": { "contacts": [ { "id": "3789r1-2A4E", "name": "Maria", "numbers": [ { "number": "+55 86 99999-0001", "label": "Celular" } ], "hasPhoto": true } ] } }
```

Searches the phone's contacts by name or number, up to `limit` contacts, those whose name starts with the query first. Numbers are as stored on the phone, `label` in the phone's language. The contacts stay on the phone: the Mac asks as the user types and keeps only the latest results. Without the contacts permission the phone answers `error` (`permission`).

### `photo.request` / `photo` — Mac → phone / phone → Mac

```json
{ "type": "photo.request", "id": "p1", "body": { "contact": "3789r1-2A4E" } }
{ "type": "photo", "replyTo": "p1", "body": { "contact": "3789r1-2A4E", "data": "/9j/4AAQ…" } }
```

The contact's thumbnail, base64 (JPEG or PNG, a few KB). No answer when the contact has no photo. The Mac asks once per contact and connection.

### `notification.posted` — phone → Mac

```json
{ "type": "notification.posted", "body": { "key": "0|com.whatsapp|1|xyz|10123", "app": "com.whatsapp", "appName": "WhatsApp", "title": "Maria", "text": "Chego às 8", "time": 1792360000000, "actions": [ { "id": 0, "title": "Responder", "reply": true }, { "id": 1, "title": "Marcar como lida", "reply": false } ], "silent": false, "icon": "iVBORw0KGgo=" } }
```

A new or updated notification on the phone. `key` is Android's notification key: an update carries the same key and replaces the Mac's copy. `time` is in milliseconds since 1970. `actions` are the notification's buttons, `id` being the button's position; `reply` marks the ones that take text. `silent` is set on updates the app asked not to alert for. `icon` is the app's icon as a 96×96 PNG, base64, sent with the app's first notification on each connection and left out after that; the Mac keeps it on disk.

The phone leaves out ongoing notifications (music, downloads, its own), group summaries, notifications that can't be dismissed, low-importance ones, calls (shown by `call.state`), and those the app marked as local to the phone.

### `notification.removed` / `notification.active` — phone → Mac

```json
{ "type": "notification.removed", "body": { "key": "0|com.whatsapp|1|xyz|10123" } }
{ "type": "notification.active", "body": { "keys": [ "0|com.whatsapp|1|xyz|10123" ] } }
```

`notification.removed` when a notification leaves the phone. `notification.active` once after `hello`, with the keys still on the phone, so the Mac drops the copies of notifications removed while they were apart. Notifications posted while apart are not sent later.

### `notification.action` / `notification.dismiss` — Mac → phone

```json
{ "type": "notification.action", "id": "n4", "body": { "key": "0|com.whatsapp|1|xyz|10123", "action": 0, "reply": "Ok, até já" } }
{ "type": "notification.dismiss", "body": { "key": "0|com.whatsapp|1|xyz|10123" } }
```

Press a notification's button, with `reply` for the ones that take text, or dismiss the notification on the phone.

### `notification.filter` — Mac → phone

```json
{ "type": "notification.filter", "body": { "muted": [ "com.instagram.android" ] } }
```

The apps whose notifications the phone should not send. Sent after `hello` and whenever the user changes it in the Mac's settings; the phone keeps it until the next one.

### `clipboard` — both directions

```json
{ "type": "clipboard", "body": { "text": "Rua das Flores, 123 — apto 4" } }
```

Text the user chose to send to the other side's clipboard, up to 100,000 characters. Only sent on an explicit action: the Mac's "Enviar Texto Copiado" menu item, or sharing text to "Enviar para o Mac" on the phone. Neither side watches the clipboard.

### `ring` — both directions

```json
{ "type": "ring", "body": { "on": true } }
```

From the Mac, starts (`on: true`) or stops ringing the phone so the user can find it. The phone plays its ringtone on the alarm stream at full volume, so it rings in silent mode too, vibrates and shows a notification that stops it; it stops on its own after a minute and puts the alarm volume back. The phone sends `ring` back each time it starts or stops, so the Mac's menu follows it.

### `calls.recent` — phone → Mac

```json
{ "type": "calls.recent", "body": { "calls": [ { "number": "+5586999990001", "name": "Maria", "contact": "3789r1-2A4E", "kind": "missed", "time": 1760700000000, "duration": 0 } ] } }
```

The phone's latest calls, newest first, up to 8. Sent after `hello` and whenever the call history changes; not sent without the call log permission. `kind` is `incoming`, `outgoing`, `missed` or `declined` (blocked calls count as declined), `time` is in milliseconds since 1970 and `duration` in seconds. `number` is left out for private numbers; `name` and `contact` when the number isn't a contact.

### `gallery.request` / `gallery.results` / `gallery.import` — Mac → phone / phone → Mac / Mac → phone

```json
{ "type": "gallery.request", "id": "g1", "body": { "limit": 8 } }
{ "type": "gallery.results", "replyTo": "g1", "body": { "photos": [ { "id": "1000012345", "name": "20261017_111110.jpg", "time": 1760700000000, "thumbnail": "/9j/4AAQ…" } ] } }
{ "type": "gallery.import", "body": { "id": "1000012345" } }
```

The latest photos on the phone, newest first, up to `limit` (at most 24), each with a JPEG thumbnail of about 200 pixels in base64. The Mac asks each time its menu opens. `gallery.import` asks the phone to send that photo, which it does as a regular phone-to-Mac file transfer. Without the photos permission the phone answers `error` (`permission`).

### File transfers

Files don't travel on the main connection, so a large one never holds up pings, calls or notifications. Each transfer gets its own connection: the phone opens a new TLS connection to the Mac's port, with the same certificates, and its first message says what it's for instead of `hello`. The Mac accepts it only from a paired phone.

```json
{ "type": "transfer.upload", "body": { "id": "t1", "name": "IMG_2041.jpg", "size": 3145728, "mime": "image/jpeg" } }
{ "type": "transfer.offer", "body": { "id": "t2", "name": "Relatório.pdf", "size": 48213, "mime": "application/pdf" } }
{ "type": "transfer.download", "body": { "id": "t2" } }
{ "type": "transfer.chunk", "body": { "id": "t1", "data": "/9j/4AAQSkZJRg==" } }
{ "type": "transfer.result", "body": { "id": "t1", "ok": true } }
```

- **Phone to Mac:** the phone opens a transfer connection and sends `transfer.upload`, then the file as `transfer.chunk`s.
- **Mac to phone:** the Mac sends `transfer.offer` on the main connection; the phone opens a transfer connection, sends `transfer.download` with the offer's `id`, and the Mac sends the chunks. An offer nobody downloads within a minute is dropped.
- Chunks carry up to 256 KB each, base64. When the receiver has `size` bytes it answers `transfer.result` (`ok`, and a `message` when it isn't) and the sender closes the connection. A connection that closes before then cancels the transfer, and the receiver throws away what it got.
- The receiver treats `name` as a file name only: the Mac drops any path and leading dots and numbers copies ("foto (1).jpg"); the phone saves into `Download/Galaxy Bridge`.

### `error` — both directions

```json
{ "type": "error", "replyTo": "c7a2", "body": { "code": "permission", "message": "O Galaxy Bridge não tem permissão para fazer ligações." } }
```

| `code` | |
|---|---|
| `version` | Incompatible protocol version. |
| `permission` | The phone is missing a permission the request needs. |
| `failed` | Anything else. `message` is shown to the user. |

### `ping` / `pong` — Mac → phone / phone → Mac

```json
{ "type": "ping" }
```

## Fixtures

`fixtures/` has one file per message. Both test suites decode each one, encode it again and compare the JSON, so the two implementations can't drift apart.
