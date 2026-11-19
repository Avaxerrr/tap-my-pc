# Architecture

## Overview

One Windows process hosts the WPF application, tray integration, local-network API, prototype web assets, and background feature services. The projects below define code boundaries, not separate executables or Windows services.

```text
Browser remote / Flutter Android client
                    |
   Pinned HTTPS over Wi-Fi / Bluetooth RFCOMM
                    |
             Core feature handlers
                    |
         Windows-specific implementations

WPF view models call the same core handlers.
Bluetooth carries the same authenticated HTTPS API through a process-owned loopback listener, reusing the same core handlers.
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

Bluetooth radio control uses a separate Core interface and asynchronous command handler. Windows implements it with WinRT radio APIs, filters exclusively for Bluetooth adapters, and requests change permission on the WPF Dispatcher only when needed. The status endpoint reads radio state without requesting permission. This feature uses the existing Wi-Fi API; Bluetooth command transport is implemented separately through WindowsRfcommServer and Desktop/Connections/BluetoothConnectionHost. It forwards encrypted bytes to a fixed loopback ApiHost and shares the same feature handlers, pairing, timers, and activity.

Audio output and per-monitor controls have dedicated Core interfaces with Windows implementations. HardwareCommands validates selections/ranges and publishes shared activity. The API serves device lists separately from the two-second status poll; the phone refreshes them on connection, after commands, on request, or on the ten-second foreground retry cadence when a list previously failed. Monitor I/O runs off the UI thread, serializes changes, briefly caches reads, and always releases native physical-monitor handles. Built-in brightness uses WMI where available; external displays use DDC/CI.

ShortcutCatalog owns the locally approved list. Only the PC settings UI can add/remove entries, persisted through LocalSettings. Remote clients receive names, kinds, and opaque IDs, then request launch by ID. The Windows launcher resolves the approved target and uses Windows shell launching without remotely supplied command lines or arguments. App paths and website URLs are not exposed in remote list responses.

## API and Flutter transition

- Start with a documented, versioned API under `/api/v1`.
- Use transport DTOs that do not expose WPF or Windows implementation types.
- Define consistent success/error responses, supported capabilities, and units such as volume and timer duration before implementing endpoints.
- Prefer explicit desired-state operations where possible. Prevent automatic retries from duplicating non-idempotent power or timer actions.
- Separate command acceptance from confirmed device state, especially for power transitions that end the connection.
- The Windows host owns timers, paired-client records, preferences, and authoritative state.
- Flutter implements its own UI and API client while reusing the server behavior and protocol. A documented command contract, not a shared programming language, provides compatibility.
- Bluetooth is a byte transport adapter for the existing HTTPS API. Keep feature handlers independent of transport; do not duplicate commands or add a speculative transport framework.

Implemented routes and DTOs are documented in [API contract](api.md). The web remote polls status every two seconds while visible. It stores a bearer token locally; the PC persists only its hash and client metadata. Pairing uses a locally generated, single-use six-digit code that expires after five minutes or five incorrect attempts. Remote clients cannot generate pairing codes.

## Local-network access

Pairing and authenticated commands are required. Kestrel serves HTTPS with the existing per-user certificate and separate listeners for the selected trusted local IPv4 adapter and an optional active Tailscale adapter, using the same configured port. Local Automatic excludes Tailscale; LAN listeners still require Windows Private/Domain classification. Configure > Remote access explicitly enables Tailscale, recognized by adapter metadata plus its default IPv4 range. Each network listener recovers independently; global Stop persists and closes LAN, Tailscale and Bluetooth. Both network listeners and Bluetooth serve authenticated networkConnection location hints through the same API; clients verify saved TLS identity before using a hint. Local discovery advertises only LAN. Android stores separate address slots and offers Automatic (local, Tailscale, Bluetooth), Local network only, Tailscale only and Bluetooth only. Only status recovery can change routes, never command replay. Legacy explicit Tailscale host settings migrate to Automatic LAN with Tailscale enabled. Legacy Android combined-network preferences migrate according to their saved address. See [Tailscale remote access](tailscale.md), [setup](setup.md) and [mobile connections](mobile-connections.md). Origin/Host checks, request limits and per-IP rate limiting remain.

## Mobile connections and monitoring

Manual browser pairing remains available. The desktop saves the active certificate reference in identity.json. It reuses the certificate across selected-IP changes and automatically renews it within 30 days of expiry, preserving the persisted RSA identity key. An expired certificate can renew with its existing key; a missing/unusable key requires confirmed local recovery. Android now supports QR enrollment, protected saved profiles, and explicit PC selection. The QR carries a one-use secret and exact leaf fingerprint; verification of that leaf precedes secret transmission. The phone derives its stable key pin from the TLS certificate, never discovery or an unverified payload. Shared pairing state atomically consumes both QR and manual paths. Desktop image rendering uses QRCoder; native Android decoding uses bundled ML Kit through mobile_scanner. Native Android NSD discovers _tapmypc._tcp hints; saved-pin HTTPS authentication validates candidates before updating stored addresses. Desktop advertising is limited to its selected trusted adapter. Connection preference persists, auto-starts by default, waits on Public/unidentified networks, and rebinds after network changes. Initial QR generation occurs only with no paired clients; subsequent enrollment is explicit. Authenticated status includes Bluetooth address/service metadata. Android saves per-PC Automatic/Wi-Fi-only/Bluetooth-only preferences. Bluetooth uses the same TLS identity checks before credentials, remains usable when Wi-Fi is unavailable, and shares the remembered Start/Stop choice. First-time enrollment stays on Wi-Fi. See [Bluetooth](bluetooth.md). Android learns a SHA-256 SubjectPublicKeyInfo pin only from a verified TLS peer, stores it with the saved profile, and accepts valid renewed certificates with that same key. Legacy leaf-only profiles migrate on their next verified connection; without prior migration they need a fresh QR after renewal. Confirmed local reset creates a new key, persistently revokes all phones and invitations, and retains PC timers and connection preference. See [mobile connections](mobile-connections.md). Discovery provides address hints rather than trust; connection failure must never redirect commands to another PC. AP isolation is a reachability issue.

The Windows monitoring source reads cached PC Stats Tray snapshots on loopback. The TapMyPC API serves them through its paired connections. Android polls while its Stats tab is open and the app is in the foreground. [Hardware monitoring](monitoring-integration.md)

## Android Wake-on-LAN

Windows computes a subnet broadcast address from the active LAN listener’s adapter and prefix and provides it with the adapter MAC and UDP port 9 in authenticated status. Android caches the last valid hint on that PC’s secure profile and gives saved manual values priority. The phone builds a magic packet from the configured adapter MAC and checks that its destination is on a connected Wi-Fi network. It binds the UDP socket to Wi-Fi when no VPN applies. With a VPN active, it uses Android’s normal routing for local destinations that the VPN leaves on the LAN. Destinations are limited to local IPv4 routes or the IPv4 limited broadcast. An explicit tap sends a single packet. Existing pinned HTTPS status polling confirms that the selected PC is reachable after wake. An unreachable PC stays Offline during background retries. Wake delivery feedback remains visible independently of that status.

After Windows resumes, the desktop restarts the RFCOMM listener if connections are enabled. Android discards a failed status connection and opens a fresh connection during recovery. The Windows host keeps its paired-client records, identity, and pending timers during listener recovery.

## Android Remote Desktop preview

The optional UltraVNC service captures the physical Windows console and handles input. The service runs separately from TapMyPC and accepts connections only from the PC itself in the supported configuration. Desktop composes the fixed loopback backend endpoint on the LAN and Tailscale API listeners. Core persists the opt-in for each paired client, owns one session across both routes, and cancels it when that permission or pairing is revoked. API authenticates the WebSocket and forwards binary bytes between it and the local backend after verifying the RFB greeting. Closing the listener also stops its active stream. A negotiated WebSocket subprotocol lets the client report successful VNC sign-in on its active socket. Core tracks the viewer for the desktop dashboard and the activity feed publishes its connection and disconnection. The dashboard offers a setup shortcut while the service or its local-only configuration is missing. Clients without the subprotocol continue streaming binary RFB. Desktop settings delegate service status, setup, repair, password reset, and capture options to the Windows adapter. An elevated action reads the publisher’s latest stable release and verifies the x64 installer’s published checksum, version, and signing publisher when the service is missing. An existing compatible service is reused. The Windows adapter writes the service INI and verifies the local listener after starting it. A private local named pipe ties the elevated process to the WPF host and delivers setup progress, any chosen password, and the generated password result. Both ends verify the peer PID. WPF offers the credential choice on fresh setup or explicit reset. The portable TapMyPC distribution downloads the installer on demand.

Flutter opens the WebSocket on the selected PC with the existing saved TLS pin and bearer credential. An Android WebView loads the bundled noVNC assets and exchanges binary data over an origin-restricted AndroidX WebKit message bridge. The pairing token and network socket stay in Dart. Optional VNC passwords are stored with the corresponding paired profile using the phone's secure storage after successful authentication. The viewer forwards input to the real Windows screen and stays open through sign-in. The viewer makes a delayed full-frame request after VNC sign-in. Windows lock and unlock update a revision in authenticated status, which prompts an immediate full-frame request and a delayed follow-up. The Flutter toolbar and options sheet control keyboard, rotation, display scaling, quality, and manual refresh. The WebView reports the VNC framebuffer dimensions, scales it locally, and handles keyboard input. Flutter saves the last image quality preset on the phone and applies it before RFB negotiation in the next session. The relay carries framebuffer updates and input only. The viewer closes when the user disconnects or the app goes to the background. See [setup](setup.md#remote-desktop-preview).

## Action feedback and presentation

Core `RemoteCommands` coordinates immediate audio/media/display commands. `ActionFeed` provides ordered, bounded activity records without referencing WPF or HTTP. `PowerScheduler` owns the shared feed and emits schedule, cancellation, execution, and failure notices. The API returns command feedback and includes recent activity in status, allowing Flutter to reuse the same behavior.

The desktop subscribes on its Dispatcher for dashboard activity and silent non-activating feedback windows. Pending power actions show a final countdown and cancellation on the PC. Presentation observers cannot fail command execution. The web client shows immediate loading, server feedback, errors, and a sticky pending-action banner. See [action feedback](action-feedback.md) for native-overlay limitations and semantics.

Account for Windows Firewall, network interface selection, and router client isolation during setup. Do not silently expose the API on every network or configure public internet access. Any firewall changes must be explicit and scoped to the intended local-network access.

## Remote presence

PairingService keeps an in-memory last-authenticated timestamp and trusted listener transport per paired client. Successful API authentication refreshes it; stored pairings, rejected credentials, pairing itself, and blocked cross-origin/Host requests do not establish presence. ActiveClients expires entries after ten seconds, and revocation/desktop listener stop clear them. Presence is not persisted or returned in remote status, and introduces no new polling or mobile protocol requirement.

The desktop samples this state on its existing one-second timer. The connection card shows a muted No phone connected badge when idle. Each active client has a name and a fixed-color Bluetooth, Wi-Fi, or Tailscale badge. The card border uses the shared connection color when all active clients use the same route and stays neutral for mixed routes. The title-bar dot uses the selected accent and pulses while active and visible. The pulse animates independently of Windows visual effects, with no animation clock when hidden, minimized, or idle. Successful authentication counts even when the request later fails. Authenticated browser requests and Android availability probes also count as recent reachability.

Android supplies its OS device name (model fallback) during enrollment and as an optional bounded Base64-UTF8 X-TapMyPC-Device-Name header on authenticated requests. Only valid credentials can update their own reported label. Invalid hints are ignored, and display-name persistence failures do not reject valid commands. Local PC renaming persists NameCustomized and takes precedence; credentials and identity remain unchanged. The desktop refreshes paired names as well as additions/removals.

Bluetooth listener composition supplies RemoteTransport.Bluetooth directly to ApiHost; request headers and phone transport preferences cannot set this classification. That listener rejects radio power changes before calling Core/Windows operations. The Android view and dispatch guard also disable radio changes based on the actual active client, including Automatic fallback.

## Desktop appearance

Desktop presentation owns live accent resources, drawer transitions, and responsive layout. The custom companion shadow and its native input helpers have been removed after disabling them improved dragging smoothness. MainWindow does not create or synchronize a transparent shadow window. The content window stays opaque with explicit ClearType rendering and per-monitor DPI awareness.

AppearanceViewModel persists the desktop theme and accent through LocalSettings in appearance.json, separately from connection preferences and credentials. It applies the same surface and accent colors to the main window and feedback banners and supplies them to the tray renderer. Saved accent-only settings use Dark. Drawer transitions and feedback fades are always enabled independently of Windows visual effects, with no app animation setting. Legacy motion values in appearance.json are ignored; existing accents remain compatible. Shared drawer behavior supports all three panels without changing command handlers. The native tray menu uses the same bundled Inter font through a process-private GDI+ font collection, vertically centered text, and DPI-scaled rounded corners. Tray menu colors use the same palette; the multi-resolution app/tray icon is bundled locally.

## Android presentation

The Flutter client keeps connection state, certificate pinning, discovery, command dispatch, and confirmation in the existing client layer. `mobile/lib/ui/` owns the shared theme, reusable cards/sheets, dashboard navigation, feature controls, and PC-owned timer banner. It does not add Windows operations or alter the API contract.

Remote groups sound, media, and shortcuts. Devices groups displays and Bluetooth. Power groups confirmed actions and timers configurable in seconds or minutes. Android uses `supportsImmediatePower` to choose zero delay for direct Lock, Sleep, and Hibernate. The server accepts zero-delay actions separately from cancellable timers and dispatches after writing the response. The selected PC card colors its badge using the active API transport. Pending timers remain above bottom navigation, including their last known countdown offline. Android hides expired offline countdowns and reads authoritative timer state and server time on reconnect. Switching PCs clears pending and feedback snapshots. A successful authenticated status response establishes connectivity before optional device lists load. List failures clear the affected list, show a warning, and retry on the ten-second cadence. A failed status request or authentication rejection invalidates control. Commands are sent once.

The app bundles static Inter faces and the same five accent palettes as desktop. Appearance preferences use the separate `tapmypc.appearance.v1` secure-storage key, with serialized writes and protection against a late startup read overwriting a user's choice. App appearance and desktop appearance are independent. Motion automatically follows Android accessibility preferences, without an app-level override. Legacy saved motion values are ignored; accent preferences remain compatible. The first-connection screen uses a compact app bar and a single setup card with numbered Wi-Fi pairing instructions and one Add your PC action. Installed package metadata supplies version text in Settings > About and in the header after a PC is saved; the onboarding header omits it. No duplicated UI version constant is used.

## Resource expectations

Aim for near-idle CPU while waiting for requests and modest memory use. Measure a release build with settings closed and open; prior discussion of tens of MB to around 100 MB was a rough estimate, not a verified target or guarantee.
