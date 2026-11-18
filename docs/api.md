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
| PUT | `/api/v1/audio/volume` | `{"volume":35}` | 200 `{"accepted":true}` |
| PUT | `/api/v1/audio/mute` | `{"muted":true}` | 200 `{"accepted":true}` |
| POST | `/api/v1/audio/step` | `{"direction":"Up"}` | 200 accepted + requested-key feedback |
| POST | `/api/v1/media` | `{"action":"PlayPause"}` | 200 `{"accepted":true}` |
| POST | `/api/v1/display/off` | None or `{}` | 200 `{"accepted":true}` |
| PUT | `/api/v1/bluetooth` | {"enabled":true} | 200 accepted + feedback |
| POST | `/api/v1/power` | `{"action":"Hibernate","delaySeconds":1800,"confirmed":true}` | 202 pending action object |
| DELETE | `/api/v1/power/{id}` | None | 200 `{"canceled":true}` or 404 |

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

Power actions: `Lock`, `Sleep`, `Hibernate`, `Shutdown`, `Restart`. Delay is an integer: 10–86400 seconds for shutdown/restart, 3–86400 seconds otherwise. Power requests require `confirmed:true`. Reject a second pending timer with 409 rather than replacing it. An accepted action is queued, not proof that a Windows power transition completed.

Volume is an integer from 0 to 100. Missing required command properties, malformed JSON, invalid enum values, and numeric enum values are rejected. Device names must contain 1–60 characters after considering non-whitespace content.

### Status

Status includes optional serverVersion (currently 0.3.1+4 for the desktop/server release), read from compiled API assembly metadata. Clients display it for comparison; it is informational, not an identity or protocol compatibility check.

```json
{
  "pcName": "MY-PC",
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

`audio` is null if unavailable. `pending` is null when no action is queued. `lastError` records the latest scheduler execution failure and clears when another action is scheduled. Dates are ISO 8601 UTC; clients display local time or derive remaining duration using serverTime to avoid phone clock skew. Capability flags describe available adapters/power states; individual commands can still fail because of OS policy or the target app.

`activity` contains up to 30 recent notices, newest first, with the same shape as `feedback` above. Phases are `Running`, `Succeeded`, `Requested`, `Scheduled`, `Canceled`, and `Failed`. Sequences increase within the host process and reset on restart. Activity is in memory, shared across clients, and contains no pairing secrets. `Scheduled` includes a dueAt timestamp. It is presentation feedback, not a durable audit log or proof that a power transition completed.

### Pending action response

```json
{"id":"a-guid","action":"Hibernate","dueAt":"2026-11-17T15:30:00+00:00"}
```

Use the returned ID for cancellation. An old timer ID cannot cancel a newer action. Cancellation is unavailable after dispatch starts. Closing the client does not cancel the action; exiting the Windows process does.

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

## Bluetooth connection metadata

Authenticated status includes optional bluetoothConnection: {available:boolean,address:string|null,serviceId:string,message:string|null}. The service UUID is 8cf69287-4d5e-47f1-97c8-0a4ec3b5d290; address is the PC adapter MAC. Clients learn address hints only through an authenticated, identity-verified connection. Availability failure does not invalidate Wi-Fi controls.

Bluetooth carries the existing API unchanged through encrypted RFCOMM and a fixed loopback HTTPS listener. The same TLS identity, bearer credentials, route validation, revocation, feedback, and timer state apply. No unauthenticated Bluetooth command route or localhost authorization exemption exists. See [Bluetooth](bluetooth.md).

## Discovery and remaining protocol work

Desktop mDNS advertises _tapmypc._tcp on the selected trusted adapter, with v=1, fp=certificate SHA-256 fingerprint, pk=SubjectPublicKeyInfo SHA-256 fingerprint, and name=machine name in TXT records. Android NSD resolves saved-PC address hints, then verifies pinned HTTPS and authenticated status before updating the saved address. Advertisements never contain command tokens or pairing secrets and never authorize access. Same-key renewal and explicit local identity reset are implemented; see [mobile connections](mobile-connections.md).

Monitoring is planned after Bluetooth. This contract does not promise a metrics endpoint; the proposed future bridge is recorded in [monitoring integration](monitoring-integration.md).

## Flutter and Bluetooth

Flutter implements native presentation/client code and stores credentials using mobile secure storage. It verifies the host certificate identity through QR/manual pairing and exact certificate pinning on every connection. Do not copy the simulator's validation exception into production.

Bluetooth will require its own connection and authorization protocol; it should call the same core services rather than depend on HTTP endpoints. Bluetooth framing, platform roles, and libraries have not been selected.
