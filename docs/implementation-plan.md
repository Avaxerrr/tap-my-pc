# Implementation plan

## Current state

Coordinated development build: 0.3.0 (build 3), with automatic trusted-network connections, one-time QR setup, native Android discovery/address recovery, remembered multi-PC selection, and in-app connection help. See [setup](setup.md).

The app is branded **TapMyPC**, with the tagline **Your PC, a tap away.** The solution, project namespaces, executable, tray, dashboard, web UI, and documentation use this name. Compatibility code preserves the pre-rename preferences, paired-client credentials, certificates, and single-instance behavior.

The first prototype is implemented on .NET 10: the four main projects, WPF tray/settings UI, HTTPS host, pairing/revocation, web remote, Windows control adapters, and PC-owned timers. A separate loopback-only simulator supports testing without Windows actions. See [verification](verification.md) for evidence and outstanding checks.

The next usability pass is implemented: automatic network-address selection with legacy settings migration, a frameless dashboard with Advanced settings, shared command activity/progress, non-activating PC feedback and power countdowns, web loading/success/error cues, and Windows volume-key requests for relative volume controls. The update is staged separately while the original app is running; see [setup](setup.md#apply-a-staged-update).

Automated HTTPS and headless browser tests use simulated controls. The user subsequently confirmed phone connectivity over Wi-Fi after selecting the Wi-Fi listen address. Certificate trust, tray interaction, startup registration, and disruptive native controls still need further manual verification when the user is no longer gaming. The agent did not start or expose the real host during the initial verification.

Bluetooth radio status and explicit on/off commands are now implemented over Wi-Fi, with Windows permission handling, compact PC feedback, and simulated tests. This does not implement Bluetooth as a transport. Shutdown already exists as both a direct confirmed action and a scheduled timer. Bedtime presets are deferred at the user's request.

The compact desktop UI now uses the approved dark card design at 680 × 640 with embedded Inter fonts. Pairing, activity, and configuration use exclusive side panels; startup and notification preferences stay on the main screen. This presentation update preserves host commands and tray lifecycle.

The desktop polish pass adds sharper widgets, non-overlapping shortcut feedback, explicit text smoothing and per-monitor DPI handling, scrollbar hover/drag feedback, reversible drawer animations with a system/On/Off policy, locally saved accent palettes, an independent outer shadow, a branded tray/app icon and dark tray menu, and responsive wide/vertical layouts. Host commands, authentication, and timer semantics are unchanged.

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

## Phase 3: Selected additions

Implemented audio output switching, locally approved app/website shortcuts, and per-monitor brightness/on/off with capability detection. The user has deferred presets and remote input. Revisit remote wake alongside the mobile app rather than during this desktop/web pass.

## Phase 4: Flutter client â€” in progress

The first Android client is implemented in mobile/ using the existing manual enrollment API, exact certificate verification, secure profile storage, multiple saved PCs, and native controls. QR enrollment is now implemented with single-use secrets and pinned certificate verification. Native discovery, authenticated address recovery, certificate reuse across IP changes, and remembered host startup are implemented. Certificate renewal/recovery remains a next protocol step. See [mobile setup](../mobile/README.md).

1. Define stable PC identity and migrate address-based certificate lifecycle; specify renewal/reset/recovery.
2. Implement locally opened, short-lived, single-use QR enrollment with identity verification and protected per-PC credentials.
3. Implemented: native Android discovery, last-address/manual fallback, authenticated reconnection, availability and permission/error feedback. Do not infer AP isolation from timeouts.
4. Support home desktop/work laptop profiles with independent trust/state and explicit command targets.
5. Implemented: remembered Start/Stop connections, automatic startup on trusted networks and rebind after network changes; Windows sign-in startup stays separate.
6. Build Flutter controls/timers against the existing API. Verify Android first, then iPhone with macOS/Xcode.
7. Test wrong identities, QR expiry/reuse, revocation, IP changes, isolation, permissions, PC switching, and reconnects without command replay.

Reuse core behavior and rebuild presentation in Dart. Manual browser setup remains a fallback. See [mobile connections](mobile-connections.md).

Monitoring is explicitly deferred and does not block mobile work. Preserve PC Stats Tray and its website when revisiting the [recorded bridge proposal](monitoring-integration.md). Presets/remote input stay deferred; revisit remote wake alongside mobile development with hardware-specific investigation.

## Phase 5: Bluetooth and optional wake

Before building the Bluetooth UI, prove command exchange between Windows and each mobile platform. Choose roles, protocol, and libraries based on actual compatibility, including Windows adapter capabilities. Reuse core command handlers and define Bluetooth-specific authorization and connection behavior.

Remote wake is a separate investigation. Test supported power states explicitly; Bluetooth or Wi-Fi connectivity while awake does not prove wake capability.

## Open decisions

- Installer approach; the initial output is a framework-dependent folder publish.
- QR/discovery and existing certificate migration are implemented. Automatic certificate renewal and identity-recovery UX remain. Manual address/code pairing remains available.
- USB networking and authenticated routed/relayed access are exploratory; no public-network or AP-isolation fallback is implemented.
- Media targeting when several applications are playing.
- Future Bluetooth protocol and Windows peripheral/central support.

Implemented decisions: HTTPS with per-user self-signed certificates; revocable bearer credentials stored as hashes on the PC; local JSON preferences; explicit listen address; status polling every two seconds while visible; ten-second minimum shutdown/restart countdown, three-second minimum for other power actions; one pending timer with explicit cancellation before replacement. Timers are canceled on host-process exit and do not survive restart. [API details](api.md) and [setup](setup.md) document the behavior.

Resolve each decision when needed and record the implemented choice in the relevant document. These are implementation choices, not reasons to block all independent work.

## Earlier local inspection

A read-only inspection during planning reported a Realtek 8852CE WiFi 6E PCI-E NIC, traditional S3 sleep and hibernate support, and the Wi-Fi adapter listed as wake-programmable but not wake-armed. No settings were changed and no wake test was performed. Recheck before relying on this information; it is not proof of WoWLAN support from any particular power state.
