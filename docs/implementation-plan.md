# Implementation plan

## Current state

| Component | Current development version |
| --- | --- |
| Windows desktop and API | **0.16.7 (build 34)** |
| Android | **0.18.3 (build 47)** |

The Windows tray host serves the browser remote and authenticated API. It manages pairing, command feedback, and power timers. Android uses QR or manual pairing and saves independent PC profiles. It can reconnect over the local network, Tailscale, or Bluetooth. [Setup](setup.md) · [Mobile connections](mobile-connections.md)

Windows and Android connection badges use the theme text color for their icons and labels, including offline. Windows uses its theme accent for the outer connection card border. Android offers long-press actions and a TapMyPC Controls widget for a paired PC. [Connection feedback](setup.md#phone-names-and-connection-feedback) · [Home-screen controls](../mobile/README.md#home-screen-controls)

Both apps provide About TapMyPC with version copying, in-app setup help, third-party licenses, and a link to the GitHub repository. On Windows, About opens inside the Configure drawer. Android includes the PC host version when it is available.

Android supports local Wake-on-LAN and the PC Stats Tray integration. The Remote Desktop preview supports Wi-Fi and Tailscale, optional PC audio, and a Windows-managed UltraVNC service. Its remaining hardware and network checks are tracked below. See the verification history for earlier versions, test results, and package installation status. [Verification history](verification.md)

## Phase 1: Foundation and first remote command — implemented

1. Select a supported .NET SDK and establish the solution boundaries described in [architecture](architecture.md).
2. Implement WPF startup, tray lifecycle, settings window, and dependency injection.
3. Define the initial versioned API contracts, errors, capabilities, and pairing/authentication flow. Document them alongside implementation.
4. Serve a simple responsive remote page from the embedded API host.
5. Connect an Android browser over home Wi-Fi and verify an authenticated, reversible command such as setting volume or mute.

Verify unauthorized requests are rejected, invalid input is handled, and the listener stays available after settings close. Resolve local-network setup and firewall behavior explicitly.

## Phase 2: Browser remote — implemented

1. Add the initial audio, media, display, and power controls from [product scope](product-scope.md).
2. Add PC-owned timers, pending-action status, cancellation, and power confirmation behavior.
3. Show capabilities, connection status, unsupported operations, and actionable failures.
4. Complete startup preferences and paired-client management.
5. Check release-build memory and idle CPU, and test the phone layout on actual devices.

Verify timers continue after browser disconnection and cancellation prevents the scheduled action. Use focused automated tests for scheduling, validation, and authentication behavior. Verify Windows effects manually where appropriate; do not run disruptive power actions as unattended tests on the development PC.

## Phase 3: Selected additions

Implemented audio output switching, locally approved app and website shortcuts, and per-monitor brightness and power controls with capability detection. Presets and a standalone remote touchpad or keyboard remain deferred. Android Wake-on-LAN and viewer input are covered below.

## Phase 4: Android client — implemented

Android provides QR and manual enrollment, pinned HTTPS, protected per-PC credentials, multiple selectable profiles, and the remote controls and timers. It discovers and verifies saved PCs and keeps their pending actions, connection state, and preferences separate. Desktop connections can resume automatically on trusted networks. Android and Windows support same-key certificate renewal and explicit local identity reset. iOS remains deferred. [Android build and test guide](../mobile/README.md) · [Mobile connections](mobile-connections.md)

## Phase 5: Bluetooth secondary connection — implemented

Proved an encrypted Classic RFCOMM exchange on the development PC and Android phone. Windows advertises a secure custom RFCOMM service and forwards to a fixed process-owned loopback HTTPS listener; native Android forwards opaque TLS bytes to the Dart client. Existing TLS identity verification, bearer credentials, commands, feedback, timers, and revocation are reused. No separate command dispatcher is needed.

Android saves Automatic, Local network only, Tailscale only, or Bluetooth only per PC. First enrollment and Bluetooth-address learning use authenticated Wi-Fi; saved phones can then control without LAN access. Global Start/Stop controls the LAN, Tailscale, and Bluetooth listeners. Public-network restrictions apply to the local LAN listener. Only read-only status recovery can switch transports; commands are never replayed. iOS remains deferred. See [Bluetooth](bluetooth.md).

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

The viewer supports landscape fullscreen, Fit and pannable Fill, saved custom stream settings, and diagnostics. It centers the desktop after scaling, can recover a stalled resize by reconnecting, and restores the saved PC audio choice when the host allows it. [Viewer setup and controls](setup.md#remote-desktop-preview) · [Stream implementation](architecture.md#android-remote-desktop-preview)

### Deferred viewer work

Validate monitor selection and check UltraVNC server-side scaling on the target setup, including touch accuracy and sign-in text readability.

### Deferred: black patches after Windows unlock

The Android viewer can stay mostly black after Windows unlocks. Touching the screen or moving content reveals individual patches. The user confirmed that **Refresh screen** restores the entire image. They observed it at 5 FPS and saw it clear at 25 and 60 FPS in initial checks. Repeat the comparison before attributing the issue to the capture limit.

The original device baseline was TapMyPC Windows 0.15.2+26 and Android 0.14.1+29 with UltraVNC 1.8.3.2. The viewer could also open to an all-black image that **Refresh screen** restored. Android 0.15.0+30 adds a one-second follow-up full-frame request after VNC sign-in and after the PC reports a Windows desktop switch. The same release adds the compact toolbar, rotation, Fit and Fill, capture-resolution reporting, and a saved image quality preset.

Windows updates `remoteDesktopRevision` on lock and unlock. The Android status poll passes it to the viewer, which uses the same non-incremental RFB request as **Refresh screen**. The exact capture timing on the target PC is still unverified.

- [ ] Compare repeated unlocks at 5, 25, and 60 FPS with the same viewer quality and no phone input after sign-in. Check whether Android receives the unlock revision and requests a full frame. Compare the request time with the first usable desktop image.
- [ ] Repeat cold viewer opens and lock/unlock transitions with the current Android build. Leave the phone untouched and observe whether the delayed refresh restores the entire screen.
- [ ] If the follow-up fails, compare TapMyPC and the native UltraVNC viewer in separate sessions against the same server to narrow down the cause.
- [ ] Verify that the whole desktop appears automatically after repeated lock and unlock cycles over both Wi-Fi and Tailscale, without touching the screen or pressing **Refresh screen**.

## Open decisions

- Installer approach; the initial output is a framework-dependent folder publish.
- USB networking and a possible relay for waking the PC from outside the home LAN.
- Media targeting when several applications are playing.
- Bluetooth compatibility across more adapters and Android background behavior.

Implemented decisions include HTTPS with per-user self-signed certificates, hashed revocable bearer credentials, local JSON preferences, explicit listen address, and two-second status polling while visible. Direct Android Lock, Sleep, and Hibernate can dispatch immediately. The PC owns one cancellable timer and requires explicit cancellation before replacement. Positive delays start at three seconds for Lock, Sleep, and Hibernate and ten seconds for Restart and Shut down. Host-process exit cancels pending work. [API details](api.md) and [setup](setup.md) document the behavior.

Resolve each decision when needed and record the implemented choice in the relevant document. These are implementation choices, not reasons to block all independent work.

## Earlier local inspection

A read-only inspection during planning reported a Realtek 8852CE WiFi 6E PCI-E NIC, traditional S3 sleep and hibernate support, and the Wi-Fi adapter listed as wake-programmable but not wake-armed. No settings were changed and no wake test was performed. Recheck before relying on this information; it is not proof of WoWLAN support from any particular power state.
