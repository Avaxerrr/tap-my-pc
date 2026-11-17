# Implementation plan

## Current state

The app is branded **TapMyPC**, with the tagline **Your PC, a tap away.** The solution, project namespaces, executable, tray, dashboard, web UI, and documentation use this name. Compatibility code preserves the pre-rename preferences, paired-client credentials, certificates, and single-instance behavior.

The first prototype is implemented on .NET 10: the four main projects, WPF tray/settings UI, HTTPS host, pairing/revocation, web remote, Windows control adapters, and PC-owned timers. A separate loopback-only simulator supports testing without Windows actions. See [verification](verification.md) for evidence and outstanding checks.

The next usability pass is implemented: automatic network-address selection with legacy settings migration, a frameless dashboard with Advanced settings, shared command activity/progress, non-activating PC feedback and power countdowns, web loading/success/error cues, and Windows volume-key requests for relative volume controls. The update is staged separately while the original app is running; see [setup](setup.md#apply-a-staged-update).

Automated HTTPS and headless browser tests use simulated controls. The user subsequently confirmed phone connectivity over Wi-Fi after selecting the Wi-Fi listen address. Certificate trust, tray interaction, startup registration, and disruptive native controls still need further manual verification when the user is no longer gaming. The agent did not start or expose the real host during the initial verification.

## Phase 1: Foundation and first remote command

1. Select a supported .NET SDK and establish the solution boundaries described in [architecture](architecture.md).
2. Implement WPF startup, tray lifecycle, settings window, and dependency injection.
3. Define the initial versioned API contracts, errors, capabilities, and pairing/authentication flow. Document them alongside implementation.
4. Serve a simple responsive remote page from the embedded API host.
5. Connect an Android browser over home Wi-Fi and verify an authenticated, reversible command such as setting volume or mute.

Verify unauthorized requests are rejected, invalid input is handled, and the listener stays available after settings close. Resolve local-network setup and firewall behavior explicitly.

## Phase 2: Useful web prototype

1. Add the initial audio, media, display, and power controls from [product scope](product-scope.md).
2. Add PC-owned timers, pending-action status, cancellation, and power confirmation behavior.
3. Show capabilities, connection status, unsupported operations, and actionable failures.
4. Complete startup preferences and paired-client management.
5. Check release-build memory and idle CPU, and test the phone layout on actual devices.

Verify timers continue after browser disconnection and cancellation prevents the scheduled action. Use focused automated tests for scheduling, validation, and authentication behavior. Verify Windows effects manually where appropriate; do not run disruptive power actions as unattended tests on the development PC.

## Phase 3: Presets and selected additions

Add Bedtime presets, followed by audio output switching and approved app shortcuts as needed. Agree on preset failure behavior and timer persistence requirements before implementing them.

## Phase 4: Flutter client

1. Create the Flutter mobile project and consume the existing Wi-Fi API.
2. Implement pairing, secure credential storage, connection status, controls, and timers.
3. Verify on Android first, then iPhone with access to macOS/Xcode build tooling.
4. Decide whether to retain the web remote as an optional fallback.

Reuse the Windows agent and API. Rebuild client presentation and connection handling in Dart; do not promise automatic conversion of web UI code.

## Phase 5: Bluetooth and optional wake

Before building the Bluetooth UI, prove command exchange between Windows and each mobile platform. Choose roles, protocol, and libraries based on actual compatibility, including Windows adapter capabilities. Reuse core command handlers and define Bluetooth-specific authorization and connection behavior.

Remote wake is a separate investigation. Test supported power states explicitly; Bluetooth or Wi-Fi connectivity while awake does not prove wake capability.

## Open decisions

- Installer approach; the initial output is a framework-dependent folder publish.
- Discovery/QR codes; the prototype uses a manual address and six-digit pairing code.
- Media targeting when several applications are playing.
- Future Bluetooth protocol and Windows peripheral/central support.

Implemented decisions: HTTPS with per-user self-signed certificates; revocable bearer credentials stored as hashes on the PC; local JSON preferences; explicit listen address; status polling every two seconds while visible; ten-second minimum shutdown/restart countdown, three-second minimum for other power actions; one pending timer with explicit cancellation before replacement. Timers are canceled on host-process exit and do not survive restart. [API details](api.md) and [setup](setup.md) document the behavior.

Resolve each decision when needed and record the implemented choice in the relevant document. These are implementation choices, not reasons to block all independent work.

## Earlier local inspection

A read-only inspection during planning reported a Realtek 8852CE WiFi 6E PCI-E NIC, traditional S3 sleep and hibernate support, and the Wi-Fi adapter listed as wake-programmable but not wake-armed. No settings were changed and no wake test was performed. Recheck before relying on this information; it is not proof of WoWLAN support from any particular power state.
