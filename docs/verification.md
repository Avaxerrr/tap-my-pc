# Verification

This is a chronological record. Earlier sections describe their build at the time; the v0.3.0 automatic-connections section records the latest delivered behavior and checks.

## First prototype checks

Performed on the user's Windows development machine on November 17, 2026, without opening a visible application window or issuing native mutating controls while the user played a game.

- Release solution build: passed with warnings treated as errors.
- Automated suite: 13 tests passed, covering single-use/expired/locked pairing, token persistence as hashes, revocation, timer dispatch/cancellation/conflicts/unsupported states/errors/exit, actual loopback HTTPS hosting, protected commands, static assets, malformed requests, and Origin/Host rejection. Controllers are simulated in these tests.
- Headless installed-Chrome browser smoke: passed pairing, volume/mute, timer scheduling/cancellation, confirmation dismissal, saved-credential reload, and responsive layout at 390-pixel phone width. No JavaScript errors or horizontal overflow were observed. Commands targeted only the isolated simulator.
- WPF settings view: rendered and inspected offscreen without showing or activating a window. This verifies visual construction, not interactive tray behavior or real settings bindings.
- Read-only Windows adapter probe: audio COM access and sleep/hibernate capability queries succeeded. No volume, mute, media, display, or power setting was changed.

Screenshots are generated under `artifacts/screenshots` and are not source-controlled. Browser verification is reproducible through [setup](setup.md#simulator).

## Usability update checks

- Release build: zero warnings/errors; 22 automated tests pass. Added checks cover automatic/manual/stale address selection, no silent localhost fallback, actual audio-state feedback, ordered/bounded activity, observer isolation, honest requested-media semantics, command failure events, timer lifecycle notices, and validated volume-key requests.
- Headless Chrome: confirmed immediate sending notification, spinner, disabled controls/aria-busy during a simulated 800ms request delay, visible error feedback, and a sticky timer/cancel banner, in addition to the existing pairing/control/reload/layout checks.
- Frameless WPF dashboard and custom audio feedback window rendered offscreen and were visually inspected. No window was activated, no overlay was shown, and no actual media/volume/power inputs were sent.
- An isolated offscreen harness also checked legacy settings migration to Automatic, preservation of a new explicit localhost override, actual dashboard binding initialization, pairing-code generation, and cancellation through the dashboard command. It used temporary settings under artifacts and a simulated controller; no user preferences or Windows controls were changed.
- The usability build was staged separately and the user's running original host was left untouched. The update script checks for a running installed copy before copying and was not applied during development. New builds use the TapMyPC name and publish paths following the rename.

Automatic selection rechecks the available private IPs when starting; a network change while the host is already listening still requires stop/start. Custom overlay focus behavior, final-countdown interaction, WindowChrome drag/resize/maximize, and Windows native flyout behavior need real interactive testing.

## TapMyPC rename checks

- Renamed solution/projects/namespaces, dashboard/tray/OSD/web branding, certificate exports, documentation, and executable metadata. The published desktop executable is `TapMyPC.exe`.
- All 22 automated tests pass after the rename; the renamed release publish succeeds.
- Headless browser verification additionally checks that the old browser credential migrates to the TapMyPC storage key and the page title uses TapMyPC.
- An isolated offscreen harness verified fallback reads of old host preferences and paired-phone credentials, plus revocation writing new data without modifying legacy files. Dashboard/feedback views rendered after namespace changes.
- Legacy certificate reuse and already-enabled startup-entry migration are implemented but have not been exercised against the user's actual certificate/registry stores during this rename.

## Still required

- User confirmed phone browser connectivity over Wi-Fi after switching the listener from loopback to the Wi-Fi address. The browser still reports an untrusted certificate; full verification of certificate identity/trust and both Android/iPhone clients remains outstanding. This does not confirm every native control was exercised.
- Interactive WPF settings bindings, tray reopen/exit, paired-client management, and sign-in startup.
- Actual volume/mute, media-key handling, monitor-off, lock/sleep/hibernate/shutdown/restart behavior, and Windows failures/unsaved-work handling.
- Release-host idle CPU and memory measurement. No measured resource claim is made yet.

No firewall rule, startup entry, network-profile change, certificate trust entry, or Wi-Fi listener was enabled by the agent during the initial verification. The user subsequently launched the host and connected a phone. The .NET CLI's first-run setup automatically installed its standard untrusted development certificate; the app's per-address certificates are created when its real host is started.

## Compact notification update

- Release build and staged publish succeeded with zero warnings/errors; all 22 existing automated tests passed.
- Rendered the actual WPF feedback control offscreen for media, mute, volume errors, scheduled timers, and final countdowns. Routine cards measure 320 × 68 pixels at 96 DPI; cancellation and longer error messages fit without clipping.
- Normal volume notifications are suppressed only in the desktop presenter. Volume errors, mute/media/power feedback, phone responses, and shared activity history are retained.
- No native volume/media/display/power commands were issued for this verification. Interactive fade/focus behavior and clicking countdown cancellation still require manual testing.

## Bluetooth radio controls

- Release build/publish succeeded with zero warnings/errors. All 25 automated tests passed, including authenticated Bluetooth updates, required boolean validation, unavailable-adapter failures, and requested-versus-confirmed state feedback.
- Headless Chrome verified Bluetooth off-confirmation dismissal, simulated off/on transitions, state labels, disabled buttons for the current state, existing controls, mobile layout, and reload. No browser script errors were observed.
- A read-only Windows probe enumerated this PC's Bluetooth radio and reported Off, Available=true, CanControl=true. It did not request radio-control permission or change any state.
- Actual Windows permission consent and radio on/off transitions still require manual testing. No real Bluetooth peripherals were disconnected, and no shutdown/power command was executed.

## Audio switching, approved shortcuts, and monitor controls

- Release solution build and folder publish succeeded with zero warnings/errors. All 36 automated tests passed.
- Tests cover authenticated device routes, stale audio/monitor IDs, brightness range validation, unsupported monitor controls, per-monitor targeting, local shortcut persistence/removal, save rollback, URL/path validation, and rejection of unapproved launch targets.
- Headless Chrome verified simulated audio output switching, approved website launch, per-monitor brightness/on/off, disabled unsupported controls, existing Bluetooth/audio/power behavior, reload, and responsive layout. No script errors or horizontal overflow were observed.
- An isolated offscreen WPF harness checked actual shortcut view-model approval/validation and rendered the expanded settings form for visual inspection. Its store and launchers were simulated; no real apps or websites were launched.
- A read-only native probe enumerated four connected audio outputs, identified the default MOMENTUM 4 endpoint, and confirmed the audio-policy COM interface is available. It did not switch outputs.
- The initial monitor probe falsely reported DISPLAY1 (GBT2726) as unsupported because the adapter discarded its valid zero-valued physical-monitor handle. This was corrected on November 18; see the M27QA detection correction below.
- Actual output changes, Windows app/website launching, and supported-monitor brightness/power transitions still require manual testing. No audio output, monitor brightness/power, or PC power state was changed by the agent.

## M27QA detection correction — November 18, 2026

- The user confirmed ClickMonitorDDC can control the M27QA over the same direct HDMI connection. A focused read-only diagnostic found DXVA2 returns physical-monitor handle 0, which our adapter had incorrectly treated as missing.
- Direct calls using that handle successfully read brightness 20/100, contrast 50/100, speaker volume 50/100, and power state 1 (on). These were reads only.
- Physical handles are now nullable: null represents failed enumeration, while every returned numeric handle, including zero, is retained for queries and commands.
- Release build passed without warnings/errors and all 36 automated tests passed. A native read-only regression check through the corrected public controller reports brightness=20, CanSetBrightness=true, CanSetPower=true, and IsOn=true for GBT2726.
- Brightness writes and monitor off/on recovery still require user testing; no settings or power states were changed by the agent.

## User feedback and mobile design status — November 18, 2026

The user subsequently reported the corrected monitor controls work. This is user feedback, separate from the agent's read-only native probes.

At that planning checkpoint, QR enrollment, automatic discovery/reconnection, mobile secure storage, multi-PC profiles, and remembered host startup were plans. Subsequent implementation and checks are recorded below. Monitoring integration is explicitly deferred. See mobile-connections.md and monitoring-integration.md for boundaries and required future validation.

## First Android client — November 18, 2026

- Desktop controls and planning checkpoint committed/pushed as ef6e306 before mobile implementation.
- Flutter analysis reported no issues; two Dart validation tests passed and the Android debug APK built.
- Device integration test passed on the user's USB-connected Android 16 phone (23122PCD1G): wrong certificate pin rejected, subsequent valid enrollment succeeded, secure profile save/load passed, and the native UI connected and executed a simulated mute command.
- Test used only the loopback simulator through adb reverse, with ephemeral certificate/code and restored prior profiles. No native PC control was exercised.
- At this first-client checkpoint, mobile enrollment was manual address/fingerprint/code. QR, discovery, address-independent identity, Bluetooth transport, custom timer durations, and iOS builds remain future work. This test is not a full security audit.

## QR pairing — November 18, 2026

- Release build/publish passed without warnings/errors. All 42 backend tests and five Flutter tests passed.
- Backend checks cover 256-bit QR secrets, shared QR/manual single-use state, expiry, regeneration, explicit closure, five-failure lockout, concurrent redemption, required API properties, normal authorization, replay rejection, and revocation.
- Rendered the actual desktop pairing view model and dashboard offscreen; the QR, fallback code, expiry, and generate button fit the pairing card.
- The USB-connected Android device decoded that desktop-generated QR PNG with the bundled native decoder, rejected a wrong TLS pin before submitting the secret, enrolled successfully, rejected replay, saved/loaded the secure profile, and connected in the native UI. Prior device profiles were restored.
- No real PC controls were invoked. The test used an isolated loopback HTTPS host with simulated controllers and a temporary invitation; camera permission prompts and aiming the live camera at a monitor remain manual checks.
- Automatic discovery, stable identity migration, Bluetooth transport, iOS, and monitoring remain outside this change.

## Version visibility and QR setup guidance

- Desktop and Android builds now declare 0.2.0, build 2. Desktop file/product metadata reports 0.2.0.2 / 0.2.0+2. Android reads versionName/versionCode from the installed package through its native channel rather than a duplicated display constant.
- Desktop title bar shows the compiled version, the phone header shows its installed version, and authenticated status includes serverVersion for display on the phone.
- Pairing instructions distinguish offline Start host from online Generate pairing QR. The existing URL remains for browser access; no QR is shown before a pairing invitation is generated.
- Release solution build/publish and offscreen WPF layout/shortcut checks passed. Changes affect display/build metadata and additive status metadata; QR secret and authentication behavior are unchanged.

- Android installed metadata was verified as versionName=0.2.0 and versionCode=2; the on-device header was visually confirmed as v0.2.0 (build 2). Flutter analysis is clean. Both versioned development builds were applied and reopened.

## Automatic connections — v0.3.0 (build 3), November 18, 2026

- .NET tests: 42 passed. Flutter tests: 7 passed. Flutter analyze: no issues. Release desktop publish and normal debug APK build succeeded.
- Isolated WPF lifecycle harness passed: automatic startup, initial QR, successful pairing hides QR, persisted Stop survives a new view model, explicit resume, subsequent launch without QR, authenticated saved credential reconnect, and reuse of the exact certificate for another IP. Only simulated device controls and a temporary certificate/settings store were used; the harness removed its own test certificate afterward.
- Read-only Windows network-category probe recognized the selected Private Wi-Fi adapter and rejected the untrusted virtual adapter. No firewall or network-category changes were made.
- Connected Android 16 integration test passed with a simulated host on the local Wi-Fi address: actual desktop mDNS advertisement -> native Android NSD -> QR enrollment -> wrong-certificate rejection -> replay rejection -> remembered selection among two saved PCs -> automatic recovery from an unreachable saved address -> pinned authenticated LAN status -> protected address update -> in-app help dialog. No native PC control action was executed.
- Inspected the rendered desktop dashboard after pairing: QR hidden, optional browser details collapsed, Add another phone and Stop connections visible, installed version shown.
- Desktop staged update applied to the original executable path and launched. Normal Android APK installed after USB-install approval, launched, and visible version/package metadata confirmed as 0.3.0 / build 3. APK copied to artifacts/mobile/TapMyPC-debug.apk. A final lifecycle check also verified Stop connections persists while waiting on the untrusted virtual adapter.
- Remaining manual coverage: live camera aiming/permission prompts, actual DHCP/network-switch timing on varied routers, sleep/resume and lengthy discovery loss, managed network policy, certificate renewal/replacement recovery, and long-term multi-PC operation. Automated tests do not constitute a production security audit.

## Compact desktop design — November 18, 2026

- Applied the approved dark card layout at 680 × 640 (minimum 640 × 560), with bundled static Inter Regular/Medium/SemiBold/Bold and its OFL license. No system font installation is needed.
- Release build and publish passed without warnings. An isolated harness instantiated the compiled MainWindow with sample data and verified embedded-font resolution, exclusive pairing/activity/configuration panels, Escape and backdrop dismissal, network selection label/dropdown, compact dimensions, and close-to-tray behavior. No real device commands or host were started by that harness.
- Rendered the compiled default view, all panels, expanded advanced settings, a demonstration QR, and the minimum window size with long feedback and a pending action. Content scrolls when needed; the pending-action Cancel control remains available.
- Newly generated invitations automatically open the pairing panel; input labels, switch accessibility names, keyboard focus outlines, dark network controls, and local command feedback were retained or added. Transport and Windows command behavior are unchanged.
- Published to TapMyPC-next, applied through tools/Apply-Update.ps1 to the usual executable path, and launched the updated app; the process reported responding. User preferences and paired devices were preserved. Live phone/native command interaction remains a manual check.

## Desktop polish � November 18, 2026

- Release desktop build passed. The existing behavior/API suite passed all 42 tests.
- The isolated compiled-WPF harness verified persisted appearance choices without modifying saved host preferences, live accent/motion updates through the actual SettingsViewModel, animated opening/closing and rapid reversal, panel switching, disabling motion mid-transition, expanded and compact layouts, network label/dropdown behavior, Escape/backdrop dismissal, font resource resolution, and hide-to-tray. No native command was executed, and no real host was started by the harness.
- Shadow lifecycle checks verified non-activation/taskbar exclusion, minimize/restore handling, and hiding alongside the main window. The tray icon loaded from the compiled resource, and the custom dark menu rendered successfully with standard menu controls retained for navigation/dismissal.
- Visually inspected rendered compact/wide layouts in Blue and Mint and the Configure panel. Shortcut feedback is on its own wrapping row; lists grow within a bounded fraction of window height. Motion defaults to Follow Windows; persisted On/Off overrides are independent of system effects.
- Live text smoothness at the user's display scaling and the perceived shadow strength still require user assessment. The offscreen screenshots do not reproduce monitor subpixel rendering.

- Published and applied the polish build through tools/Apply-Update.ps1 to the usual executable path, then launched it. The updated TapMyPC main window was present and its process reported responding.
- Moved main-card command/pairing feedback to its own 11.5-DIP wrapping line below the 13-DIP network summary. The compiled layout harness verified that feedback is smaller and positioned below the address; release build/publish passed. The updated release is staged in TapMyPC-next while the existing installed app remains running.

## Tray menu typography and corners

- Tray menu now loads the bundled static Inter font privately for GDI+ measurement and drawing, avoiding the prior Segoe UI choice and GDI font fallback. No system font installation or font-setting changes are required.
- Rows have explicit DPI-scaled heights, text is vertically centered, and popup/hover surfaces use modest rounded corners. Native ContextMenuStrip behavior and Open/Exit actions remain intact; the main-window shadow is unchanged.
- Release build and compiled UI harness passed. The tray-specific check confirmed the Inter family, rounded window region, centered text bounds, and themed hover rendering. Inspected the resulting normal/selected menu screenshots.
- Reduced tray menu dimensions to the measured Inter text width plus modest padding, removing the fixed minimum width. Row heights now follow font metrics with compact vertical padding (33 px instead of 45 px at the verification display's DPI). Rendered menu and compiled alignment/font checks passed; release publish staged while the installed app remains running.
