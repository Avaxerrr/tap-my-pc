# Implementation plan

## Current state

Installed Android 0.9.4+21 shows a steady Offline status, reports when a wake packet was sent, and preserves the parent settings screens when leaving the wake and address editors. The Wi-Fi wake sender supports an active split-tunnel VPN. Wake PC appears first in the Power action grid, which shows why wake is unavailable while connected or when settings are missing. Setup is in Settings for both automatic and manual profiles. Android learns local Wi-Fi settings from authenticated status on desktop 0.9.0+13. Saved manual settings take priority. See [setup](setup.md#android-wake-on-lan).

Unpacked desktop 0.8.0+12 and the previous Android build 0.8.0+14 add simultaneous local/Tailscale listeners, separate saved endpoints, authenticated address learning, four connection choices and IP-only manual setup with the port under Advanced. Pairing, pinned HTTPS and no-command-replay behavior are preserved. See [Tailscale setup](tailscale.md) and verification.md for checks and package status.

Certificate lifecycle and Bluetooth secondary connectivity are implemented. Hardware monitoring in the app is next. Media information is lower priority unless a small implementation is justified. Certificate renewal/recovery is implemented before Bluetooth: same-key automatic renewal, protected Android key-pin migration, and confirmed local reset with revocation/re-pairing. The Bluetooth builds are desktop 0.6.0+10 and Android 0.6.2+12, including the earlier certificate work and the compact Android first-connection screen. Installation and validation results are recorded in verification.md. These priorities supersede earlier deferral and phase-order notes below.

Previous installed desktop/server development build: **0.3.4 (build 7)**, removing the custom companion shadow for smoother dragging and showing a muted No phone connected badge until a remote is active, keeping app animations enabled independently of Windows effects, and removing the animation setting, alongside dashboard/tray polish, themed PC feedback, and recent-authenticated-remote visibility. Android is **0.4.3 (build 7)** with a desktop-matched UI, Remote/Devices/Power navigation, persistent timer/feedback presentation, saved accent themes, and installed version visibility. The Android polish patches keep selected navigation icons white in every accent theme, follow Android reduced motion automatically, and isolate optional device-list failures from verified PC connectivity. The desktop updater now preserves nested runtime dependencies; its earlier flat copy omitted the Windows monitoring library and caused monitor-list errors. QR pairing, pinned discovery/address recovery, and multi-PC selection are preserved. See [setup](setup.md) and [versioning](versioning.md).

The app is branded **TapMyPC**, with the tagline **Your PC, a tap away.** The solution, project namespaces, executable, tray, dashboard, web UI, and documentation use this name. Compatibility code preserves the pre-rename preferences, paired-client credentials, certificates, and single-instance behavior.

The first prototype is implemented on .NET 10: the four main projects, WPF tray/settings UI, HTTPS host, pairing/revocation, web remote, Windows control adapters, and PC-owned timers. A separate loopback-only simulator supports testing without Windows actions. See [verification](verification.md) for evidence and outstanding checks.

The next usability pass is implemented: automatic network-address selection with legacy settings migration, a frameless dashboard with Advanced settings, shared command activity/progress, non-activating PC feedback and power countdowns, web loading/success/error cues, and Windows volume-key requests for relative volume controls. The current desktop and Android builds are installed and verified; see [verification](verification.md). Future desktop updates are staged while the app runs and applied after a normal tray exit; see [setup](setup.md#apply-a-staged-update).

Automated HTTPS and headless browser tests use simulated controls. The user subsequently confirmed phone connectivity over Wi-Fi after selecting the Wi-Fi listen address. Certificate trust, tray interaction, startup registration, and disruptive native controls still need further manual verification when the user is no longer gaming. The agent did not start or expose the real host during the initial verification.

Bluetooth radio status and explicit on/off commands are implemented over Wi-Fi, with Windows permission handling, compact PC feedback, and simulated tests. Bluetooth transport is also implemented separately; radio changes are disabled and rejected over that transport. Shutdown already exists as both a direct confirmed action and a scheduled timer. Bedtime presets are deferred at the user's request.

The compact desktop UI now uses the approved dark card design at 680 × 640 with embedded Inter fonts. Pairing, activity, and configuration use exclusive side panels; startup and notification preferences stay on the main screen. This presentation update preserves host commands and tray lifecycle.

The desktop polish pass adds sharper widgets, non-overlapping shortcut feedback, explicit text smoothing and per-monitor DPI handling, scrollbar hover/drag feedback, reversible drawer animations enabled independently of Windows effects, locally saved accent palettes, removal of the outer shadow after drag-performance comparison, a branded tray/app icon and dark tray menu, and responsive wide/vertical layouts. Host commands, authentication, and timer semantics are unchanged.

PC notification banners now share the desktop's Inter typography, dark surfaces, accent palette, modest corners, and brief appearance fades, while preserving silent non-activation and countdown cancellation. The main connection card and title-bar dot now show recent authenticated remote presence, with a ten-second inactivity timeout and a pulse only while the dashboard is visible.

The connection-feedback follow-up adds phone OS/model names with local PC overrides, actual per-client transport labels, Wi-Fi-only radio controls with explicit On/Off state, and server enforcement against Bluetooth self-disconnection. Current builds are desktop 0.6.0+10 and Android 0.6.2+12; see verification.md for delivery status.

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

## Phase 4: Flutter client — in progress

The first Android client is implemented in mobile/ using the existing manual enrollment API, exact certificate verification, secure profile storage, multiple saved PCs, and native controls. QR enrollment is now implemented with single-use secrets and pinned certificate verification. Native discovery, authenticated address recovery, certificate reuse across IP changes, and remembered host startup are implemented. Same-key certificate renewal and local recovery are implemented; migration and compatibility limits are in mobile-connections.md. See [mobile setup](../mobile/README.md).

1. Implemented: same-key renewal, legacy profile migration, and confirmed local identity reset/re-pairing.
2. Implement locally opened, short-lived, single-use QR enrollment with identity verification and protected per-PC credentials.
3. Implemented: native Android discovery, last-address/manual fallback, authenticated reconnection, availability and permission/error feedback. Do not infer AP isolation from timeouts.
4. Support home desktop/work laptop profiles with independent trust/state and explicit command targets.
5. Implemented: remembered Start/Stop connections, automatic startup on trusted networks and rebind after network changes; Windows sign-in startup stays separate.
6. Build Flutter controls/timers against the existing API. Verify Android first, then iPhone with macOS/Xcode.
7. Test wrong identities, QR expiry/reuse, revocation, IP changes, isolation, permissions, PC switching, and reconnects without command replay.

Reuse core behavior and rebuild presentation in Dart. Manual browser setup remains a fallback. See [mobile connections](mobile-connections.md).

Monitoring is the next implementation after completed Bluetooth work. Preserve PC Stats Tray and its website using the [recorded bridge proposal](monitoring-integration.md). Presets/remote input stay deferred. The laptop wake investigation was brought forward and is now closed for its current configuration; monitoring remains next.

## Phase 5: Bluetooth secondary connection — implemented

Proved an encrypted Classic RFCOMM exchange on the development PC and Android phone. Windows advertises a secure custom RFCOMM service and forwards to a fixed process-owned loopback HTTPS listener; native Android forwards opaque TLS bytes to the Dart client. Existing TLS identity verification, bearer credentials, commands, feedback, timers, and revocation are reused. No separate command dispatcher is needed.

Android saves Automatic/Wi-Fi-only/Bluetooth-only selection per PC. First enrollment and Bluetooth-address learning use authenticated Wi-Fi; saved phones can then control without LAN access. Global Start/Stop controls both listeners, while Public-network restrictions apply to Wi-Fi. Only read-only status recovery can switch transports; commands are never replayed. iOS remains deferred. See [Bluetooth](bluetooth.md).

## Phase 6: Hardware monitoring

Implement the [PC Stats Tray bridge](monitoring-integration.md) and Android monitoring presentation. Keep the standalone collector and website intact, reuse cached samples, and show stale/unavailable data without disabling remote controls. Decide monitoring update rates and Bluetooth payload suitability during design.

## Phase 7: Remote wake — Android sender implemented

Laptop investigation closed November 18, 2026: treat Wi-Fi wake as unavailable on the current Legion 5 Pro configuration after independent sender and Wolow failures, despite verified awake packet delivery and armed wake settings. Ethernet is documented by Lenovo but remains untested and impractical at this location. Android sends wake packets using per-PC settings over local Wi-Fi. Sleep and hibernate wake are user-confirmed with Wolow on the desktop after enabling PCIe resume. The same tests are pending with TapMyPC. See [remote wake investigation](wake-investigation.md) for evidence and limits. Hardware monitoring is next; no further laptop sleep test is pending.

## Open decisions

- Installer approach; the initial output is a framework-dependent folder publish.
- QR/discovery and existing certificate migration are implemented. Automatic same-key certificate renewal and explicit local identity reset are implemented; seamless migration requires an updated phone to connect before its first renewal. Manual address/code pairing remains available.
- Direct Tailscale HTTPS is implemented through independent opt-in listening and separate saved endpoints; see [Tailscale setup](tailscale.md). USB networking and other routed/relayed access remain exploratory. No public listener or general AP-isolation fallback is implemented.
- Media targeting when several applications are playing.
- Bluetooth uses Windows Classic RFCOMM server and Android secure RFCOMM client roles. Wider adapter/background behavior needs further testing.

Implemented decisions: HTTPS with per-user self-signed certificates; revocable bearer credentials stored as hashes on the PC; local JSON preferences; explicit listen address; status polling every two seconds while visible; ten-second minimum shutdown/restart countdown, three-second minimum for other power actions; one pending timer with explicit cancellation before replacement. Timers are canceled on host-process exit and do not survive restart. [API details](api.md) and [setup](setup.md) document the behavior.

Resolve each decision when needed and record the implemented choice in the relevant document. These are implementation choices, not reasons to block all independent work.

## Earlier local inspection

A read-only inspection during planning reported a Realtek 8852CE WiFi 6E PCI-E NIC, traditional S3 sleep and hibernate support, and the Wi-Fi adapter listed as wake-programmable but not wake-armed. No settings were changed and no wake test was performed. Recheck before relying on this information; it is not proof of WoWLAN support from any particular power state.
