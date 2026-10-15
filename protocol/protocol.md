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

**Keep-alive:** after 2 minutes without any message from the phone, the Mac sends `ping`, and the phone answers `pong`. If nothing arrives within 60 seconds of the `ping`, the Mac closes the connection. The phone closes it after 6 minutes without any message and reconnects. When the phone shuts down or restarts, it closes the connection first, so the Mac notices at once.

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
