# API contract v1

HTTPS origin: `https://<selected-PC-IPv4>:45831`. JSON uses camelCase property names and string enums. The website and Flutter use the same routes. No cloud service is required.

## Authentication and transport

Except for pairing, every `/api` request needs `Authorization: Bearer <token>`. Tokens are 32 cryptographically random bytes encoded as 64 hexadecimal characters. The PC stores SHA-256 hashes, client names/IDs, and creation times; tokens are returned only when pairing. They remain valid until revoked on the PC.

Pairing codes can only be generated locally in WPF. Codes are single-use, last five minutes, and lock after five incorrect attempts. Do not retry pairing or non-idempotent commands automatically.

Browser requests must originate from the same HTTPS origin; no CORS access is granted. Native clients may omit Origin. Host must match the bound address (localhost is also accepted for loopback). Request bodies are limited to 4096 bytes. Rate limit: 120 requests per minute per source IP, shared by assets and API calls. There are no credential-bearing query parameters.

Successful authenticated requests also refresh a transient desktop presence indicator for the corresponding paired client. Presence expires after ten seconds without activity and is cleared on revocation or desktop listener stop. Pairing alone and rejected authentication do not count. Native availability probes and browser traffic count as activity; this does not indicate a permanent connection or which PC is selected. No additional request/header, endpoint, persisted credential field, or status payload change is required.

## Routes

| Method | Route | JSON request | Result |
| --- | --- | --- | --- |
| POST | `/api/v1/pair` | `{"code":"123456","name":"My Android"}` | 200 `{"token":"..."}` |
| POST | `/api/v1/pair/qr` | `{"secret":"<64 hex characters>","name":"My Android"}` | 200 `{"token":"..."}` |
| GET | `/api/v1/status` | None | 200 status object below |
| GET | `/api/v1/monitoring` | None | 200 monitoring response below |
| GET | `/api/v1/remote-desktop` | WebSocket upgrade | 101 binary VNC stream for an approved phone over LAN or Tailscale |
| PUT | `/api/v1/audio/volume` | `{"volume":35}` | 200 `{"accepted":true}` |
| PUT | `/api/v1/audio/mute` | `{"muted":true}` | 200 `{"accepted":true}` |
| POST | `/api/v1/audio/step` | `{"direction":"Up"}` | 200 accepted + requested-key feedback |
| POST | `/api/v1/media` | `{"action":"PlayPause"}` | 200 `{"accepted":true}` |
| POST | `/api/v1/display/off` | None or `{}` | 200 `{"accepted":true}` |
| PUT | `/api/v1/bluetooth` | {"enabled":true} | 200 accepted + feedback |
| POST | `/api/v1/power` | `{"action":"Hibernate","delaySeconds":1800,"confirmed":true}` | 202 pending action object or immediate acceptance feedback |
| DELETE | `/api/v1/power/{id}` | None | 200 `{"canceled":true}` or 404 |

## Remote Desktop

`GET /api/v1/status` includes `remoteDesktopEnabled` for the authenticated client on the current listener. It requires a local PC-side opt-in for that client and an eligible network route. Backend readiness is checked when the viewer connects. On Windows 0.14.0 and newer, `remoteDesktopRevision` changes when Windows locks or unlocks while the host is running. It is null for clients without access, unsupported listeners, and hosts without a session-change source. A connected viewer can request a full RFB frame when the revision changes.

Open `wss://<PC>/api/v1/remote-desktop` with the saved PC TLS pin and `Authorization: Bearer <token>`. The authenticated upgrade carries the standard RFB byte stream in binary WebSocket messages. Treat message boundaries as stream chunks. The server allows one connection across its network listeners, resolves the backend to local loopback, and ends the stream if the paired permission is removed, the client is revoked, or the listener stops.

Clients may offer the WebSocket subprotocol `tapmypc.viewer-status.v1`. If it is selected, send the UTF-8 text message `viewer-ready` once after VNC sign-in succeeds. The host uses it as a viewer-presence signal for that active authenticated socket. The relay handles the text locally and forwards only binary RFB chunks to UltraVNC. If the server selects no subprotocol, use the binary stream alone.

The upgrade returns 401 for an invalid token, 403 when the paired client lacks Remote Desktop permission, 404 on an unsupported listener, 409 while a viewer is connected, and 503 when the local VNC backend is unavailable. A request without an upgrade returns 400 for an authorized viewer. [Setup](setup.md#remote-desktop-preview)

### Remote Desktop audio

On Windows 0.16.0 and newer, `remoteDesktopAudioEnabled` in authenticated status is true or false when the listener supports audio and the client has Remote Desktop access. It reflects the separate PC-side permission for that phone. The field is null when audio is unavailable on that listener and absent on older hosts.

Open `wss://<PC>/api/v1/remote-desktop/audio` with the same pinned TLS identity and bearer credential, and offer `tapmypc.audio.opus.v1`. The endpoint allows one stream for the paired client that owns the active viewer and has reported `viewer-ready`. That report is supplied by the viewer. The separate PC-side audio permission authorizes access to system playback independently of the UltraVNC password.

Each server-to-client binary message is one raw Opus packet with 20 ms of stereo audio at 48 kHz. The flow can pause while the selected Windows endpoint is silent. Close the WebSocket to end audio while keeping the viewer open. Closing the viewer, revoking audio or desktop permission, revoking the pairing, or stopping the listener ends capture.

The audio upgrade returns 401 for a missing or invalid bearer token, 403 for missing audio permission, 404 when the listener does not expose audio, 400 for missing upgrade or subprotocol, and 409 if the viewer is unavailable or an audio stream is already open. A capture failure can close an open audio stream with code 1011. [Setup](setup.md#play-pc-audio-on-android)

## Monitoring

`GET /api/v1/monitoring` uses the usual bearer authentication. The response includes `snapshot` and `stale`. A missing collector returns `{"snapshot":null,"stale":false}`. Otherwise the snapshot contains `generatedAtUtc`, `refreshIntervalMs`, and `metrics`. A sample is stale after the greater of five seconds or three refresh intervals.

Metric entries preserve the collector's `key`, `label`, `group`, `sourceName`, `value`, `available`, `defaultVisible`, `numericValue`, `unit`, and `totalValue`. The endpoint serves cached readings and leaves command and status handling independent. [Hardware monitoring](monitoring-integration.md)

## Command details

Media actions: `PlayPause`, `Previous`, `Next`.

Volume step directions: `Up`, `Down`. These send Windows volume keys, allowing Windows to show its native overlay where supported. Step size is controlled by Windows. This POST is non-idempotent; do not automatically retry it.

Immediate audio/media/display responses also contain `feedback`. For example:

```json
{
  "accepted": true,
  "feedback": {
    "sequence": 2,
    "title": "Volume",
    "message": "Volume 35%",
    "phase": "Succeeded",
    "at": "2026-11-17T15:00:00+00:00",
    "audio": {"volume":35,"muted":false},
    "dueAt": null
  }
}
```

`audio` is included for explicit volume/mute results after reading the endpoint. Native key/media/display responses use `Requested` rather than claiming the final effect was verified.

Power actions are `Lock`, `Sleep`, `Hibernate`, `Shutdown`, and `Restart`. All require `confirmed:true`. On hosts advertising `supportsImmediatePower`, `delaySeconds: 0` accepts Lock, Sleep, and Hibernate for dispatch after the HTTP response. Positive delays are 3–86400 seconds for those actions and 10–86400 seconds for Shutdown and Restart. The server returns 409 while a timer or an immediate request is pending. Acceptance confirms that TapMyPC accepted the request. Windows execution failures are available in the scheduler state and activity history.

Volume is an integer from 0 to 100. Missing required command properties, malformed JSON, invalid enum values, and numeric enum values are rejected. Device names must contain 1–60 characters after considering non-whitespace content.

### Status

Status includes optional `serverVersion`, read from compiled API assembly metadata and displayed for comparison. A `supportsImmediatePower` value of `true` advertises support for zero-delay requests. Older hosts omit this field.

```json
{
  "pcName": "MY-PC",
  "supportsImmediatePower": true,
  "capabilities": {
    "audio": true,
    "media": true,
    "display": true,
    "sleep": true,
    "hibernate": true
  },
  "audio": {"volume": 35, "muted": false},
  "bluetooth": {"available":true,"canControl":true,"state":"On","message":null},
  "scheduler": {
    "pending": {"id": "a-guid", "action": "Hibernate", "dueAt": "2026-11-17T15:30:00+00:00"},
    "lastError": null
  },
  "activity": [],
  "serverTime": "2026-11-17T15:00:00+00:00"
}
```

`audio` is null if unavailable. `pending` describes the cancellable timer and is null when no timer is scheduled. `lastError` records the latest execution failure and clears when the host accepts another action. Dates are ISO 8601 UTC. Clients display local time or use `serverTime` to derive remaining duration. Capability flags describe available adapters and power states. Windows policy or the target app can still reject a command.

`activity` contains up to 30 recent notices, newest first, with the same shape as `feedback` above. Phases are `Running`, `Succeeded`, `Requested`, `Scheduled`, `Canceled`, and `Failed`. Sequences increase within the host process and reset on restart. Activity is in memory, shared across clients, and contains no pairing secrets. `Scheduled` includes a dueAt timestamp. It is presentation feedback, not a durable audit log or proof that a power transition completed.

### Pending action response

```json
{"id":"a-guid","action":"Hibernate","dueAt":"2026-11-17T15:30:00+00:00"}
```

Use the returned ID for cancellation. An old timer ID cannot cancel a newer action. Cancellation is unavailable after dispatch starts. Closing the client does not cancel the action; exiting the Windows process does.

Immediate requests return `{"accepted":true,"feedback":{...}}` with the regular action feedback fields and no timer ID.

## Audio outputs, approved shortcuts, and individual monitors

All routes below require the usual bearer authentication, Host/Origin checks, limits, and same-origin rules.

| Method | Route | Request / result |
| --- | --- | --- |
| GET | /api/v1/audio/outputs | Array of {id,name,isDefault}; active render outputs only |
| PUT | /api/v1/audio/output | {id:string}; accepted + feedback |
| GET | /api/v1/shortcuts | Array of {id,name,kind}; kind App or Website, no targets |
| POST | /api/v1/shortcuts/{id}/launch | Empty object; accepted + feedback |
| GET | /api/v1/monitors | Array of monitor status below |
| PUT | /api/v1/monitors/brightness | {id:string,brightness:integer}; range 0–100, accepted + feedback |
| PUT | /api/v1/monitors/power | {id:string,enabled:boolean}; accepted + feedback |

Audio output selection sets Windows defaults for playback and communications. It reports Succeeded only when the selected output is read back as the multimedia default. Disconnected IDs are rejected. Apps with explicit output routing may not follow system defaults.

Only the local PC can approve or remove shortcuts. There is no API for adding targets or passing launch arguments. Launch resolves the ID against the current saved approval list. Unknown/removed IDs return 400; a successful Windows open request reports Requested, not proof that an app finished opening. Do not automatically retry launches.

Monitor status: {id,name,brightness,canSetBrightness,canSetPower,isOn,message}. Brightness is a percentage or null; isOn is true, false, or null when unknown. Capability flags gate the controls. A monitor may become unreachable while off and need a physical power button. Missing/stale IDs and malformed values return 400; unsupported controls return 422. Brightness/power responses report Requested, with actual values available from a fresh GET.

Fetch device lists on connection, after relevant actions, or when the user requests refresh. Avoid repeatedly querying monitor hardware in the status polling loop. The Windows monitor adapter caches reads briefly and serializes hardware operations.

## Bluetooth radio control

PUT requires an explicit boolean enabled value. It applies the desired state to all Bluetooth radios, leaving Wi-Fi unchanged. Repeating the same desired state is safe. Turning Bluetooth off disconnects its peripherals; the web remote asks for confirmation first. Requests require normal bearer authentication.

Status includes bluetooth even when no adapter is present. State is On, Off, Mixed, Disabled, or Unavailable. canControl indicates that adapters are present and not hardware/system disabled; Windows can still deny change permission. message explains unavailable states. Permission is requested on the PC only when a change is needed, and Windows may show a consent prompt.

Feedback is Succeeded only when a read-back matches the desired state; accepted transitions not yet reflected in state report Requested. With multiple radios, a failure can leave a partial change: read status before deciding what to do next. Missing adapters, blocked radios, or denied access return 422 and command failures remain visible in desktop activity.

## Errors

Application errors use `{"error":"Human-readable message"}`. Framework-level malformed-request, origin/host, or rate-limit failures may have an empty body; clients must handle the HTTP status independently.

| Status | Meaning |
| --- | --- |
| 400 | Invalid payload, delay, volume, or Host |
| 401 | Missing/revoked credential, wrong/expired pairing code, or closed pairing window |
| 403 | Foreign Origin |
| 404 | No matching pending timer/route |
| 409 | Existing pending action or another operation conflict |
| 422 | Unsupported power state or unavailable/denied Bluetooth control |
| 429 | Rate limit exceeded |
| 500 | Windows operation/internal error |

A failure from an optional audio-output, monitor, or shortcut list does not invalidate a successful authenticated status response. Android keeps the PC connected and shows a warning for that list; status failure or 401 still disables control. The desktop presence indicator measures recent authentication, including requests whose operation subsequently returns an error, rather than endpoint success.

On a network timeout, a command may already have been accepted. Read status before retrying a timer request. Volume/mute set explicit state and are idempotent; media commands are not. No general idempotency-key mechanism is implemented yet.

## QR enrollment v1 — implemented

POST /api/v1/pair/qr accepts JSON {secret:string,name:string}, with both fields required, and returns {token:string}. It is exempt from bearer authentication only for enrollment and retains HTTPS, Host/Origin validation, request-size limits, and rate limiting.

Only the local desktop opens a pairing session. The desktop QR encodes a JSON object with type "tapmypc-pair", version 1, name, address (HTTPS origin), fingerprint (leaf certificate SHA-256 hex), secret (32 random bytes as 64 hex characters), and expiresAt (ISO 8601).

The mobile client validates the schema/expiry and verifies the scanned certificate before submitting the secret. The resulting token is a separate persistent credential; neither the QR nor discovery contains that token. QR images are generated locally and never served by an unauthenticated GET endpoint.

QR and six-digit code enrollment share a single five-minute window, five-invalid-attempt limit, and atomic single-use redemption. A successful QR redemption invalidates the manual code and vice versa. Regeneration or explicit closure invalidates prior invitations. Replays/expired secrets return 401; missing required properties return 400.

QR identity is the exact leaf certificate. The desktop persists its certificate reference and reuses the same leaf across IP changes. Android verifies that pin before sending any credential to a discovered address. After a verified connection Android derives and stores the peer certificate's SHA-256 SubjectPublicKeyInfo pin. Valid same-key renewals preserve saved credentials; a key reset requires local confirmation and fresh enrollment. QR v1 and HTTP routes are unchanged.

## Client display metadata and Bluetooth radio safety

Authenticated requests may include X-TapMyPC-Device-Name containing a Base64-encoded UTF-8 phone name. The server bounds the header to 512 characters and accepts only a trimmed 1–60-character name without control characters. Invalid hints are ignored. The hint updates only that credential's paired-client label unless the PC has saved a custom name. It never authorizes access, changes credentials, or determines connection transport. Older clients/servers may omit/ignore it.

Transport classification comes from the listener composition, not request data. PUT /api/v1/bluetooth returns 422 with a switch-to-Wi-Fi message on the Bluetooth listener and does not call the radio controller. Wi-Fi radio control remains available subject to reported hardware capability and explicit desired state.

## Bluetooth connection metadata

Authenticated status includes optional bluetoothConnection: {available:boolean,address:string|null,serviceId:string,message:string|null}. The service UUID is 8cf69287-4d5e-47f1-97c8-0a4ec3b5d290; address is the PC adapter MAC. Clients learn address hints only through an authenticated, identity-verified connection. Availability failure does not invalidate Wi-Fi controls.

Bluetooth carries the existing API unchanged through encrypted RFCOMM and a fixed loopback HTTPS listener. The same TLS identity, bearer credentials, route validation, revocation, feedback, and timer state apply. No unauthenticated Bluetooth command route or localhost authorization exemption exists. See [Bluetooth](bluetooth.md).

## Discovery and remaining protocol work

Desktop mDNS advertises _tapmypc._tcp on the selected trusted adapter, with v=1, fp=certificate SHA-256 fingerprint, pk=SubjectPublicKeyInfo SHA-256 fingerprint, and name=machine name in TXT records. Android NSD resolves saved-PC address hints, then verifies pinned HTTPS and authenticated status before updating the saved address. Advertisements never contain command tokens or pairing secrets and never authorize access. Same-key renewal and explicit local identity reset are implemented; see [mobile connections](mobile-connections.md).

Monitoring is planned after Bluetooth. This contract does not promise a metrics endpoint; the proposed future bridge is recorded in [monitoring integration](monitoring-integration.md).

## Flutter and Bluetooth

Flutter implements native presentation/client code and stores credentials using mobile secure storage. It verifies the host certificate identity through QR/manual pairing and exact certificate pinning on every connection. Do not copy the simulator's validation exception into production.

Bluetooth carries the same pinned HTTPS API over encrypted Classic RFCOMM with the existing pairing identity and bearer credential. Windows and Android byte adapters forward TLS without introducing a second command or authorization protocol. See [Bluetooth](bluetooth.md).

## Tailscale addressing

The existing numeric HTTPS origin may use the separately enabled Tailscale IPv4 listener alongside LAN. API routes, authentication, certificate identity and Host/Origin restrictions are unchanged. Desktop classifies requests on this listener as Tailscale for local presence; clients cannot choose that classification through headers. See [Tailscale setup](tailscale.md).

## Independent network hints (0.8.0)

Authenticated status includes optional `networkConnection` with `localAddress`, `tailscaleAddress`, and `wakeOnLan`. Each address is a nullable string. The nullable `wakeOnLan` object contains `mac` (six colon-separated octets), `destination` (IPv4 subnet broadcast), and `port` (9). Windows supplies it for the active local listener’s LAN adapter when a broadcast and valid MAC are available. Values describe currently listening numeric HTTPS endpoints, including the shared configured port. Disabled/unavailable listeners report null. Bluetooth status also includes these network hints. They are location hints only: clients must verify the saved PC identity before sending credentials to an address. Old clients can ignore the additive field; no API route version change is needed.

Listener composition classifies WiFi, Tailscale or Bluetooth presence on the PC. Headers cannot choose the transport. LAN/Tailscale/Bluetooth share pairing, identity and feature handlers. See tailscale.md for the four mobile connection modes and migration rules.
