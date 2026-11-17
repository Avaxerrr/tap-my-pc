# API contract v1

HTTPS origin: `https://<selected-PC-IPv4>:45831`. JSON uses camelCase property names and string enums. The website and Flutter use the same routes. No cloud service is required.

## Authentication and transport

Except for pairing, every `/api` request needs `Authorization: Bearer <token>`. Tokens are 32 cryptographically random bytes encoded as 64 hexadecimal characters. The PC stores SHA-256 hashes, client names/IDs, and creation times; tokens are returned only when pairing. They remain valid until revoked on the PC.

Pairing codes can only be generated locally in WPF. Codes are single-use, last five minutes, and lock after five incorrect attempts. Do not retry pairing or non-idempotent commands automatically.

Browser requests must originate from the same HTTPS origin; no CORS access is granted. Native clients may omit Origin. Host must match the bound address (localhost is also accepted for loopback). Request bodies are limited to 4096 bytes. Rate limit: 120 requests per minute per source IP, shared by assets and API calls. There are no credential-bearing query parameters.

## Routes

| Method | Route | JSON request | Result |
| --- | --- | --- | --- |
| POST | `/api/v1/pair` | `{"code":"123456","name":"My Android"}` | 200 `{"token":"..."}` |
| GET | `/api/v1/status` | None | 200 status object below |
| PUT | `/api/v1/audio/volume` | `{"volume":35}` | 200 `{"accepted":true}` |
| PUT | `/api/v1/audio/mute` | `{"muted":true}` | 200 `{"accepted":true}` |
| POST | `/api/v1/audio/step` | `{"direction":"Up"}` | 200 accepted + requested-key feedback |
| POST | `/api/v1/media` | `{"action":"PlayPause"}` | 200 `{"accepted":true}` |
| POST | `/api/v1/display/off` | None or `{}` | 200 `{"accepted":true}` |
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

## Errors

Application errors use `{"error":"Human-readable message"}`. Framework-level malformed-request, origin/host, or rate-limit failures may have an empty body; clients must handle the HTTP status independently.

| Status | Meaning |
| --- | --- |
| 400 | Invalid payload, delay, volume, or Host |
| 401 | Missing/revoked credential, wrong/expired pairing code, or closed pairing window |
| 403 | Foreign Origin |
| 404 | No matching pending timer/route |
| 409 | Existing pending action or another operation conflict |
| 422 | Unsupported power state |
| 429 | Rate limit exceeded |
| 500 | Windows operation/internal error |

On a network timeout, a command may already have been accepted. Read status before retrying a timer request. Volume/mute set explicit state and are idempotent; media commands are not. No general idempotency-key mechanism is implemented yet.

## Flutter and Bluetooth

Flutter will replace presentation/client code and store credentials using mobile secure storage. It must verify the host certificate identity through a deliberate pairing/pinning flow. Do not copy the simulator's validation exception into production.

Bluetooth will require its own connection and authorization protocol; it should call the same core services rather than depend on HTTP endpoints. Bluetooth framing, platform roles, and libraries have not been selected.
