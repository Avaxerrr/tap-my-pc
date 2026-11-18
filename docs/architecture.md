# Architecture

## Overview

One Windows process hosts the WPF application, tray integration, local-network API, prototype web assets, and background feature services. The projects below define code boundaries, not separate executables or Windows services.

```text
Browser remote / Flutter Android client
                    |
          Authenticated Wi-Fi API
                    |
             Core feature handlers
                    |
         Windows-specific implementations

WPF view models call the same core handlers.
Future Bluetooth transport calls the same core handlers.
```

The PC listener remains independent of any client screen. The web prototype is a replaceable client; its HTML/CSS/JavaScript will not automatically convert to Flutter widgets.

## Solution layout

```text
TapMyPC.sln
src/
  TapMyPC.Desktop/
    Features/{Dashboard,Pairing,Settings}/
    Tray/
  TapMyPC.Core/
    Audio/
    Bluetooth/
    Media/
    Display/
    Power/
    Timers/
    Presets/
    Devices/
  TapMyPC.Windows/
    Audio/
    Bluetooth/
    Media/
    Display/
    Power/
    Interop/
  TapMyPC.Api/
    Endpoints/
    Contracts/
    Authentication/
    wwwroot/
tests/
  TapMyPC.Tests/
mobile/                 # Flutter Android client and device tests
tools/
  TapMyPC.Simulator/
  browser-smoke.cjs
```

Create feature folders as they become necessary. Not all future feature folders above exist yet. Do not generate empty classes or abstractions for every planned feature.

## Responsibilities and dependencies

| Project | Responsibility | References |
| --- | --- | --- |
| Core | Feature behavior, commands/results, interfaces for platform operations, timer and preset coordination | No WPF, HTTP, or Windows-specific dependencies |
| Windows | Implement platform interfaces using Windows APIs; isolate native interop | Core |
| Api | ASP.NET Core endpoints, request/response contracts, remote authentication, prototype assets | Core |
| Desktop | WPF views/view models, tray lifecycle, settings UI, startup composition and dependency injection | Core, Windows, Api |
| Tests | Focused behavior and integration verification | Projects under test |

Desktop wires implementations and hosts the API through application startup/shutdown. API endpoints validate requests and call core handlers. WPF uses the same handlers through view models. Neither layer directly invokes platform APIs.

## Organization rules

- Group behavior by feature rather than accumulating unrelated methods in generic Utils or Manager classes.
- Use constructor injection and explicit ownership. Avoid global mutable state and service locator patterns.
- Keep native calls and their error handling in Windows implementations.
- Use asynchronous listeners and cancellation for background work; do not continuously poll for commands.
- Keep the tray usable when settings are closed. Closing a settings window should not accidentally terminate the listener.
- Dispose listeners and background work during application exit.
- Do not add a separate Windows service unless a concrete requirement justifies it. Interactive-session controls need particular care if that changes.

Bluetooth radio control uses a separate Core interface and asynchronous command handler. Windows implements it with WinRT radio APIs, filters exclusively for Bluetooth adapters, and requests change permission on the WPF Dispatcher only when needed. The status endpoint reads radio state without requesting permission. This feature uses the existing Wi-Fi API; Bluetooth as a command transport remains deferred.

Audio output and per-monitor controls have dedicated Core interfaces with Windows implementations. HardwareCommands validates selections/ranges and publishes shared activity. The API serves device lists separately from the two-second status poll; the phone refreshes them on connection, after relevant commands, or on request. Monitor I/O runs off the UI thread, serializes changes, briefly caches reads, and always releases native physical-monitor handles. Built-in brightness uses WMI where available; external displays use DDC/CI.

ShortcutCatalog owns the locally approved list. Only the PC settings UI can add/remove entries, persisted through LocalSettings. Remote clients receive names, kinds, and opaque IDs, then request launch by ID. The Windows launcher resolves the approved target and uses Windows shell launching without remotely supplied command lines or arguments. App paths and website URLs are not exposed in remote list responses.

## API and Flutter transition

- Start with a documented, versioned API under `/api/v1`.
- Use transport DTOs that do not expose WPF or Windows implementation types.
- Define consistent success/error responses, supported capabilities, and units such as volume and timer duration before implementing endpoints.
- Prefer explicit desired-state operations where possible. Prevent automatic retries from duplicating non-idempotent power or timer actions.
- Separate command acceptance from confirmed device state, especially for power transitions that end the connection.
- The Windows host owns timers, paired-client records, preferences, and authoritative state.
- Flutter implements its own UI and API client while reusing the server behavior and protocol. A documented command contract, not a shared programming language, provides compatibility.
- Add Bluetooth as a transport adapter when needed. Keep current handlers independent of HTTP, but avoid designing an unused transport framework now.

Implemented routes and DTOs are documented in [API contract](api.md). The web remote polls status every two seconds while visible. It stores a bearer token locally; the PC persists only its hash and client metadata. Pairing uses a locally generated, single-use six-digit code that expires after five minutes or five incorrect attempts. Remote clients cannot generate pairing codes.

## Local-network access

Pairing and authenticated commands are required. Validate inputs, limit exposed operations to supported commands, and keep credentials out of logs. Kestrel serves HTTPS using a certificate held in the current user's Personal certificate store; it does not add a root trust entry. Normal launch resumes the saved connection preference (enabled by default) and automatically selects an active IPv4 address, preferring an adapter with a gateway and then Wi-Fi. Windows Private/Domain network classification is checked separately before listening. Stop connections persists across launches, including when waiting for a trusted network. The listener still binds only one address. Localhost and manual overrides are under Advanced settings. Legacy address-only settings migrate to Automatic once; versioned explicit debug overrides are preserved. Origin/Host checks, request limits, and per-IP rate limiting constrain the API. See [setup](setup.md) for the initial certificate identity check and phone trust limitations.

## Mobile connections and deferred monitoring

Manual browser pairing remains available. The desktop saves a public certificate reference in identity.json and reuses that exact certificate across selected-IP changes; it fails closed if the saved identity is missing or expired. Android now supports QR enrollment, protected saved profiles, and explicit PC selection. The QR carries a one-use secret and pinned leaf fingerprint; certificate verification precedes secret transmission. Shared pairing state atomically consumes both QR and manual paths. Desktop image rendering uses QRCoder; native Android decoding uses bundled ML Kit through mobile_scanner. Native Android NSD discovers _tapmypc._tcp hints; saved-pin HTTPS authentication validates candidates before updating stored addresses. Desktop advertising is limited to its selected trusted adapter. Connection preference persists, auto-starts by default, waits on Public/unidentified networks, and rebinds after network changes. Initial QR generation occurs only with no paired clients; subsequent enrollment is explicit. Certificate renewal and identity recovery remain future work. See [mobile connections](mobile-connections.md). Discovery provides address hints rather than trust; connection failure must never redirect commands to another PC. AP isolation is a reachability issue.

Monitoring is deferred. The proposed bridge keeps PC Stats Tray and its website standalone, reads local cached snapshots, and serves them through TapMyPC. No monitoring dependency or elevated network host is introduced now. See [monitoring integration](monitoring-integration.md).

## Action feedback and presentation

Core `RemoteCommands` coordinates immediate audio/media/display commands. `ActionFeed` provides ordered, bounded activity records without referencing WPF or HTTP. `PowerScheduler` owns the shared feed and emits schedule, cancellation, execution, and failure notices. The API returns command feedback and includes recent activity in status, allowing Flutter to reuse the same behavior.

The desktop subscribes on its Dispatcher for dashboard activity and silent non-activating feedback windows. Pending power actions show a final countdown and cancellation on the PC. Presentation observers cannot fail command execution. The web client shows immediate loading, server feedback, errors, and a sticky pending-action banner. See [action feedback](action-feedback.md) for native-overlay limitations and semantics.

Account for Windows Firewall, network interface selection, and router client isolation during setup. Do not silently expose the API on every network or configure public internet access. Any firewall changes must be explicit and scoped to the intended local-network access.

## Remote presence

PairingService keeps an in-memory last-authenticated timestamp per paired client. Successful API authentication refreshes it; stored pairings, rejected credentials, pairing itself, and blocked cross-origin/Host requests do not establish presence. ActiveClients expires entries after ten seconds, and revocation/desktop listener stop clear them. Presence is not persisted or returned in remote status, and introduces no new polling or mobile protocol requirement.

The desktop samples this state on its existing one-second timer. The main connection card shows Remote connected and client names, while the title-bar dot uses the selected accent and an optional subtle pulse. The pulse respects the appearance motion policy and has no animation clock when hidden/minimized or idle. Activity from browser clients and native availability probes also counts; this indicates recent authenticated reachability, not an enduring socket or proof that this PC is selected on the phone.

## Desktop appearance

Desktop presentation owns live accent resources, drawer transitions, responsive layout, and a separate non-activating shadow surface. The content window stays opaque with explicit ClearType rendering and per-monitor DPI awareness; shadow effects never wrap the text surface. Windows-specific shadow-window input styles remain in Windows/Interop. Shadow visibility follows the main window, including tray hiding and maximize/minimize.

AppearanceViewModel persists accent and motion preferences through LocalSettings in appearance.json, separately from connection preferences and credentials. The motion policy is Follow Windows (default), On, or Off; drawer transitions use translation/opacity and settle immediately when motion is disabled. Shared drawer behavior supports all three panels without changing command handlers. The native tray menu uses the same bundled Inter font through a process-private GDI+ font collection, vertically centered text, and DPI-scaled rounded corners. Tray menu colors use the same palette; the multi-resolution app/tray icon is bundled locally.

## Resource expectations

Aim for near-idle CPU while waiting for requests and modest memory use. Measure a release build with settings closed and open; prior discussion of tens of MB to around 100 MB was a rough estimate, not a verified target or guarantee.
