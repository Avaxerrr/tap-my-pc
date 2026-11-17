# Architecture

## Overview

One Windows process hosts the WPF application, tray integration, local-network API, prototype web assets, and background feature services. The projects below define code boundaries, not separate executables or Windows services.

```text
Browser prototype now / Flutter client later
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
    Media/
    Display/
    Power/
    Timers/
    Presets/
    Devices/
  TapMyPC.Windows/
    Audio/
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

## API and Flutter transition

- Start with a documented, versioned API under `/api/v1`.
- Use transport DTOs that do not expose WPF or Windows implementation types.
- Define consistent success/error responses, supported capabilities, and units such as volume and timer duration before implementing endpoints.
- Prefer explicit desired-state operations where possible. Prevent automatic retries from duplicating non-idempotent power or timer actions.
- Separate command acceptance from confirmed device state, especially for power transitions that end the connection.
- The Windows host owns timers, paired-client records, preferences, and authoritative state.
- Flutter will implement its own UI and API client while reusing the server behavior and protocol. A documented command contract, not a shared programming language, provides compatibility.
- Add Bluetooth as a transport adapter when needed. Keep current handlers independent of HTTP, but avoid designing an unused transport framework now.

Implemented routes and DTOs are documented in [API contract](api.md). The web remote polls status every two seconds while visible. It stores a bearer token locally; the PC persists only its hash and client metadata. Pairing uses a locally generated, single-use six-digit code that expires after five minutes or five incorrect attempts. Remote clients cannot generate pairing codes.

## Local-network access

Pairing and authenticated commands are required. Validate inputs, limit exposed operations to supported commands, and keep credentials out of logs. Kestrel serves HTTPS using a certificate held in the current user's Personal certificate store; it does not add a root trust entry. Normal launch leaves the host stopped and automatically selects an active private IPv4 address, preferring an adapter with a gateway and then Wi-Fi. The listener still binds only one address. Localhost and manual overrides are under Advanced settings. Legacy address-only settings migrate to Automatic once; versioned explicit debug overrides are preserved. Origin/Host checks, request limits, and per-IP rate limiting constrain the API. See [setup](setup.md) for the initial certificate identity check and phone trust limitations.

## Action feedback and presentation

Core `RemoteCommands` coordinates immediate audio/media/display commands. `ActionFeed` provides ordered, bounded activity records without referencing WPF or HTTP. `PowerScheduler` owns the shared feed and emits schedule, cancellation, execution, and failure notices. The API returns command feedback and includes recent activity in status, allowing Flutter to reuse the same behavior.

The desktop subscribes on its Dispatcher for dashboard activity and silent non-activating feedback windows. Pending power actions show a final countdown and cancellation on the PC. Presentation observers cannot fail command execution. The web client shows immediate loading, server feedback, errors, and a sticky pending-action banner. See [action feedback](action-feedback.md) for native-overlay limitations and semantics.

Account for Windows Firewall, network interface selection, and router client isolation during setup. Do not silently expose the API on every network or configure public internet access. Any firewall changes must be explicit and scoped to the intended local-network access.

## Resource expectations

Aim for near-idle CPU while waiting for requests and modest memory use. Measure a release build with settings closed and open; prior discussion of tens of MB to around 100 MB was a rough estimate, not a verified target or guarantee.
