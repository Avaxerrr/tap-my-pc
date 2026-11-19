# Implementation plan

## Current state

Windows 0.15.2+26 keeps the Remote Desktop card available for setup and simplifies the viewer password dialog with a visibility toggle, inline generation, and one confirmation action. [Setup](setup.md#remote-desktop-preview)

Windows 0.15.1+25 adds an optional dashboard status card, live setup progress, and generated or custom viewer passwords with a Copy action for generated passwords. Android 0.14.1+29 adds password visibility and reports viewer readiness on a compatible Windows host. [Setup](setup.md#remote-desktop-preview)

Windows 0.15.0+24 checks for the latest stable UltraVNC installer on fresh setup and adds in-app capture service controls, password reset, and capture settings. Android 0.14.0+28 adds three viewer quality presets. [Setup](setup.md#remote-desktop-preview)

Windows 0.14.1+23 corrects the firewall rule query in Remote Desktop setup and creates a viewer password on a fresh setup from TapMyPC. [Setup](setup.md#remote-desktop-preview)

Windows 0.14.0+22 adds in-app setup for the local capture service and reports Windows lock and unlock transitions. Android 0.13.0+27 adds a full-frame refresh, a manual Refresh screen button, and opt-in VNC password saving. [Setup](setup.md#remote-desktop-preview)

Android 0.12.1+26 identifies a desktop disconnect during VNC password checking and excludes the remote viewer from automatic Android autofill. [Setup](setup.md#remote-desktop-preview)

Windows 0.13.0+21 and Android 0.12.0+25 add the experimental Remote Desktop viewer with per-phone approval, one paired stream over Wi-Fi or Tailscale, and tap and keyboard input. The Windows host uses a separately configured UltraVNC service. [Setup](setup.md#remote-desktop-preview)

Windows 0.12.0+20 adds Dark, Light, Midnight, Forest, and Plum desktop themes in **Configure → Appearance**. The chosen theme and accent update the window, tray menu, and notification banners immediately.

Windows 0.11.2+19 moves Authorized phones to the top of Configure and places Quick launch shortcuts before Appearance. Advanced Network & Security stays collapsed at the bottom.

Windows 0.11.1+18 shows PC Stats Tray status and the last sample time in **Configure → Hardware monitoring**, with setup guidance when readings are unavailable. [Hardware monitoring](monitoring-integration.md)

Windows 0.11.0+17 reads cached PC Stats Tray metrics and serves them through the paired API. Android 0.11.0+24 adds Stats with the dashboard's default and expanded views. [Hardware monitoring](monitoring-integration.md)

Windows 0.10.0+16 applies the theme accent to enabled preference switches and adds confirmed zero-delay dispatch for Lock, Sleep, and Hibernate. Android 0.10.0+23 uses the active connection's badge color, supports timers in seconds or minutes, and hides due countdowns while offline. See [verification](verification.md) for delivery status.

Windows 0.9.2+15 shows the connected phone name and its active connection on the dashboard. Bluetooth is blue, Wi-Fi is green, and Tailscale is purple. The card uses a neutral border for mixed connections. See [verification](verification.md) for delivery status.

Android 0.9.5+22 starts system pairing from Bluetooth only and waits for it to finish before switching routes. Failed status clients are closed before the next reconnect attempt. Windows 0.9.1+14 recreates the Bluetooth listener after system resume when connections are enabled. See [Bluetooth setup](bluetooth.md) and [verification](verification.md) for test and delivery status.

Installed Android 0.9.4+21 shows a steady Offline status, reports when a wake packet was sent, and preserves the parent settings screens when leaving the wake and address editors. The Wi-Fi wake sender supports an active split-tunnel VPN. Wake PC appears first in the Power action grid, which shows why wake is unavailable while connected or when settings are missing. Setup is in Settings for both automatic and manual profiles. Android learns local Wi-Fi settings from authenticated status on desktop 0.9.0+13. Saved manual settings take priority. See [setup](setup.md#android-wake-on-lan).

Desktop 0.9.0+13 supplies automatic Wake-on-LAN settings. It continues to host independent local and Tailscale listeners, and both routes share the same paired HTTPS identity. See [Tailscale setup](tailscale.md) and [verification](verification.md) for checks and package status.

Certificate lifecycle and Bluetooth secondary connectivity are implemented. Media information is lower priority unless a small implementation is justified. Certificate renewal/recovery is implemented before Bluetooth: same-key automatic renewal, protected Android key-pin migration, and confirmed local reset with revocation/re-pairing. The Bluetooth builds are desktop 0.6.0+10 and Android 0.6.2+12, including the earlier certificate work and the compact Android first-connection screen. Installation and validation results are recorded in verification.md. These priorities supersede earlier deferral and phase-order notes below.

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

The Android Stats tab uses the [PC Stats Tray bridge](monitoring-integration.md). Presets/remote input stay deferred. The laptop wake investigation was brought forward and is now closed for its current configuration.

## Phase 5: Bluetooth secondary connection — implemented

Proved an encrypted Classic RFCOMM exchange on the development PC and Android phone. Windows advertises a secure custom RFCOMM service and forwards to a fixed process-owned loopback HTTPS listener; native Android forwards opaque TLS bytes to the Dart client. Existing TLS identity verification, bearer credentials, commands, feedback, timers, and revocation are reused. No separate command dispatcher is needed.

Android saves Automatic, Local network only, Tailscale only, or Bluetooth only per PC. First enrollment and Bluetooth-address learning use authenticated Wi-Fi; saved phones can then control without LAN access. Global Start/Stop controls both listeners, while Public-network restrictions apply to Wi-Fi. Only read-only status recovery can switch transports; commands are never replayed. iOS remains deferred. See [Bluetooth](bluetooth.md).

## Phase 6: Hardware monitoring

Implemented the [PC Stats Tray bridge](monitoring-integration.md) and Android Stats tab. The tab follows the collector's refresh interval and labels stale or unavailable data.

## Phase 7: Remote wake — Android sender implemented

Laptop investigation closed November 18, 2026: treat Wi-Fi wake as unavailable on the current Legion 5 Pro configuration after independent sender and Wolow failures, despite verified awake packet delivery and armed wake settings. Ethernet is documented by Lenovo but remains untested and impractical at this location. Android sends wake packets using per-PC settings over local Wi-Fi. Sleep and hibernate wake are user-confirmed with Wolow on the desktop after enabling PCIe resume. The user reported successful desktop wake in TapMyPC after the Android VPN routing fix. See [remote wake investigation](wake-investigation.md) for evidence and limits. No further laptop sleep test is pending.

## Phase 8: Remote Desktop — prototype

The Android viewer follows the physical Windows session through the lock screen into the desktop. The user can keep watching, click, scroll, type, and open apps after signing in. This is an opt-in feature for a paired phone. Start with one display and basic input, and test over a cellular connection early.

1. **Prove the viewer.** A loopback-only browser experiment used noVNC 1.7.0 with a simulated PC. One connection rendered both screen states, sent Enter and a touch tap, and disconnected cleanly over a binary message channel. The user reported that an earlier Android preview connected to the Windows service over both Wi-Fi and Tailscale. Streaming performance still needs measurement on the target devices. [noVNC library API](https://novnc.com/noVNC/docs/API.html)
2. **Prove the Windows session.** Test the official UltraVNC Server separately in Windows service mode with local-only access. On the target desktop, verify capture and input on the locked screen with the monitor off, the configured PIN or password, and the transition into the same desktop. Repeat after sleep and hibernate. Check that disconnecting leaves Windows in its current session and that locking again permits a fresh connection. [UltraVNC service configuration](https://uvnc.com/docs/ultravnc-server/49-ultravnc-server-configuration.html)
3. **Build the in-app session.** The Android viewer and authenticated Windows stream are implemented in the preview. The simulator verified that the bundled viewer draws successive screen updates and sends touch and keyboard input. The API tests cover transport access, binary streaming, and active cancellation after permission removal. Measure time to first frame and input responsiveness on Wi-Fi and cellular with the lower-bandwidth setting during device testing. [Tailscale remote access](tailscale.md)
4. **Add away-from-home wake.** Use an optional always-on device on the home LAN to send the Wake-on-LAN packet. Verify from cellular that the user can wake the desktop, wait for TapMyPC to reconnect, sign in, and continue using Windows. The first release targets lock and resume of a signed-in Windows session. A cold boot or sign-out would require the TapMyPC listener to be available before Windows sign-in. [Wake-on-LAN over Tailscale](https://tailscale.com/blog/wake-on-lan-tailscale-upsnap)

### Remote Desktop audio preview

Windows 0.16.0+27 and Android 0.16.0+31 add optional, permission-gated playback audio over Wi-Fi and Tailscale. Windows shares a loopback copy of the default multimedia output and follows changes during a session. Verify playback on the phone, normal local playback, and output changes with the laptop speakers, DAC, and NVIDIA Broadcast. Compare delay over Wi-Fi and Tailscale. See [audio setup](setup.md#play-pc-audio-on-android).

### Android stream controls and fullscreen

Android 0.17.0+32 adds landscape fullscreen, a compact controls handle with PC audio, scrollbars in Fill, and independent RFB stream settings. The options sheet reports the received size, receive and update rates, and observed encoding and JPEG chroma. See [setup](setup.md#remote-desktop-preview).

Android 0.17.1+33 adds a bounded reconnect after an unexpected viewer interruption, more specific failure messages, and a reset to saved stream defaults. The viewer centers Fit and Fill on resize, uses full color, and shows the quality controls supported by the preferred encoding.

Android 0.17.2+34 restores Fit or Fill in a centered view at the saved stream size, compacts the dropdowns, and explains the visual tradeoffs of each encoding. Automatic and Tight use compression levels 1–9 for decoder compatibility. Zlib supports 0–9. JPEG chroma is reported in Stream details.

Android 0.17.3+36 lets UltraVNC finish its first desktop update before restoring a saved stream scale. The viewer also skips the extended desktop-size advertisement that can replace the confirmed stream size.

Android 0.17.4+37 requests a fresh frame when UltraVNC is slow to confirm a stream resize. If desktop updates stop while the resize is pending, the viewer reconnects at the selected scale. Manual refresh also works while a resize is pending.

Android 0.17.5+38 remembers the phone’s Remote Desktop audio toggle per PC and restores it on open or reconnect when the PC permits audio sharing.

### Deferred viewer work

Validate monitor selection and check UltraVNC server-side scaling on the target setup, including touch accuracy and sign-in text readability.

### Deferred: black patches after Windows unlock

The Android viewer can stay mostly black after Windows unlocks. Touching the screen or moving content reveals individual patches. The user confirmed that **Refresh screen** restores the entire image. They observed it at 5 FPS and saw it clear at 25 and 60 FPS in initial checks. Repeat the comparison before attributing the issue to the capture limit.

The original device baseline was TapMyPC Windows 0.15.2+26 and Android 0.14.1+29 with UltraVNC 1.8.3.2. The viewer could also open to an all-black image that **Refresh screen** restored. Android 0.15.0+30 adds a one-second follow-up full-frame request after VNC sign-in and after the PC reports a Windows desktop switch. The same release adds the compact toolbar, rotation, Fit and Fill, capture-resolution reporting, and a saved image quality preset.

Windows updates `remoteDesktopRevision` on lock and unlock. The Android status poll passes it to the viewer, which uses the same non-incremental RFB request as **Refresh screen**. The exact capture timing on the target PC is still unverified.

- [ ] Compare repeated unlocks at 5, 25, and 60 FPS with the same viewer quality and no phone input after sign-in. Check whether Android receives the unlock revision and requests a full frame. Compare the request time with the first usable desktop image.
- [ ] Repeat cold viewer opens and lock/unlock transitions with Android 0.15.0+30. Leave the phone untouched and observe whether the delayed refresh restores the entire screen.
- [ ] If the follow-up fails, compare TapMyPC and the native UltraVNC viewer in separate sessions against the same server to narrow down the cause.
- [ ] Verify that the whole desktop appears automatically after repeated lock and unlock cycles over both Wi-Fi and Tailscale, without touching the screen or pressing **Refresh screen**.

## Open decisions

- Installer approach; the initial output is a framework-dependent folder publish.
- QR/discovery and existing certificate migration are implemented. Automatic same-key certificate renewal and explicit local identity reset are implemented; seamless migration requires an updated phone to connect before its first renewal. Manual address/code pairing remains available.
- Direct Tailscale HTTPS is implemented through independent opt-in listening and separate saved endpoints; see [Tailscale setup](tailscale.md). USB networking and other routed/relayed access remain exploratory. No public listener or general AP-isolation fallback is implemented.
- Media targeting when several applications are playing.
- Bluetooth uses Windows Classic RFCOMM server and Android secure RFCOMM client roles. Wider adapter/background behavior needs further testing.

Implemented decisions include HTTPS with per-user self-signed certificates, hashed revocable bearer credentials, local JSON preferences, explicit listen address, and two-second status polling while visible. Direct Android Lock, Sleep, and Hibernate can dispatch immediately. The PC owns one cancellable timer and requires explicit cancellation before replacement. Positive delays start at three seconds for Lock, Sleep, and Hibernate and ten seconds for Restart and Shut down. Host-process exit cancels pending work. [API details](api.md) and [setup](setup.md) document the behavior.

Resolve each decision when needed and record the implemented choice in the relevant document. These are implementation choices, not reasons to block all independent work.

## Earlier local inspection

A read-only inspection during planning reported a Realtek 8852CE WiFi 6E PCI-E NIC, traditional S3 sleep and hibernate support, and the Wi-Fi adapter listed as wake-programmable but not wake-armed. No settings were changed and no wake test was performed. Recheck before relying on this information; it is not proof of WoWLAN support from any particular power state.
