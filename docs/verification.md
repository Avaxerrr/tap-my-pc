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

## Desktop polish — November 18, 2026

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

## Themed notifications and active remote indicator

- Core/API tests: 46 passed. New cases cover pairing without presence, rejected credentials/cross-origin requests, credential reload without presence persistence, valid authenticated traffic, expiry/refresh, multiple clients, revocation, and clearing presence without forgetting saved devices.
- An isolated compiled-WPF harness verified notification embedded Inter resolution, live Blue/Mint/Amber/Purple themes, persistent red failure styling, countdown/progress display and cancel event routing, and routine-notice reset after a countdown. Rendered normal, failure, and countdown cards were visually inspected.
- The same harness used simulated devices and an unstarted in-memory WebApplication to verify the actual SettingsViewModel/MainWindow presence bindings, connection label/client names, pulse while visible, static indicator with motion off, no pulse clock hidden/minimized, expiry/reconnection/revocation, and clearing on host shutdown. No native device action or real listener was started by this harness. Offscreen screenshots illustrate layout, not actual phone connectivity.
- Presence is intentionally based on recent authenticated traffic, including availability probes; it is not a selected-PC or persistent-socket indicator. The real-phone timeout/reconnection presentation remains a manual check.

## Desktop 0.3.1 (build 4) release and automatic version policy

- Added docs/versioning.md and a single AGENTS.md link requiring agents to apply it automatically. The policy distinguishes patch/minor/major changes, build-only test iterations, unchanged rebuilds, independent desktop/Android versions, API/schema compatibility, and safe delivery of updates to a running host.
- Desktop/server version is now 0.3.1, build 4. Directory.Build.props keeps Version and BuildNumber authoritative and derives assembly 0.3.1.0, file 0.3.1.4, and informational/product 0.3.1+4 metadata. Current release summaries were updated without rewriting historical verification entries.
- This release consolidates the accepted desktop dashboard/tray polish, themed PC notification banners, and authenticated remote-presence indicator. Android package metadata remains 0.3.0+3; no Android source, package, or version-display changes were made. API routes remain /api/v1.
- All 46 tests passed. Release publish succeeded; staged desktop and API DLLs both reported file 0.3.1.4 and product 0.3.1+4. After the user exited the old app normally, applied the staged update and reopened it. Installed DLL metadata matched, and read-only UI Automation confirmed the visible heading TAPMYPC v0.3.1 (build 4). The process reported responding.

## Android UI overhaul — 0.4.0 (build 4)

- Replaced the long mixed control list with Remote/Devices/Power navigation, a persistent selected-PC card, dedicated output/PC/activity/settings sheets, compact rectangular controls, Inter typography, and desktop-matched dark surfaces. Added independent saved Blue/Mint/Purple/Teal/Amber accents, system/On/Off motion, visible installed version/build, and matching launcher/splash styling.
- Existing certificate pinning, QR/manual enrollment, protected profile keys, discovery, exact command targets, explicit Bluetooth/power confirmation, and no-command-replay rules remain in place. Command feedback now survives status polling. Pending PC action information stays visible above navigation, including a last-known countdown with cancellation disabled offline. Desktop/server remains 0.3.1 (build 4), and the API is unchanged.
- Flutter analyze: no issues. Flutter unit/widget tests: 15 passed. New coverage includes appearance persistence without changing credential keys, empty/connected/offline/busy states, audio/output routing, navigation, persistent cancellation, PC selection, and a 320-DIP screen with enlarged text. Inspected rendered controls, settings, PC selection, and large-text previews under artifacts/mobile-ui.
- Native Android 16 integration test passed in a separate temporary applicationId (dev.tapmypc.tapmypc_mobile.uitest), against a loopback-only simulated host forwarded through adb. Verified wrong-pin rejection, enrollment, installed metadata, mute, Bluetooth-off confirmation, 30-minute scheduling and cancellation, theme persistence, help, and QR/manual layout. No real PC command was executed. The test app was uninstalled and its adb forwarding removed afterward; normal-app data was not cleared.
- Built the normal debug APK from the source-synchronized C:/temp/TapMyPC-mobile-build copy. Installed it in place with adb install -r and launched it. Android package metadata reports versionName=0.4.0 and versionCode=4; visually confirmed the visible v0.4.0 (build 4) heading and new native onboarding. Copied the distributable development APK to artifacts/mobile/TapMyPC-debug.apk. Desktop binaries and Android credentials/storage schema were not modified.
- Remaining manual checks: camera aiming/permission UX, varied phones/tablets and accessibility settings, longer foreground/background recovery, and native controls against the actual PC. This remains a debug-signed development APK; release signing and iOS deployment are not implemented.

## Android navigation contrast fix - 0.4.1 (build 5)

- Set an explicit bottom-navigation icon theme: selected icons are white, and inactive icons use the secondary text color. This avoids a dark Material default over the dark accent indicator in all five palettes.
- Added a rendered navigation regression check for selected/inactive icon colors across every palette. All 16 Flutter tests passed; Flutter analyze reported no issues. Inspected the regenerated Remote preview with its white selected icon.
- Built the debug APK from the synchronized C:/temp/TapMyPC-mobile-build source copy, copied it to artifacts/mobile/TapMyPC-debug.apk, installed in place using adb install -r, and launched it. Installed package metadata reports versionName=0.4.1 and versionCode=5.
- Bundled Inter and the existing Follow system/On/Off motion behavior are unchanged. Follow system uses Android's reduced-motion preference for app transitions; appearance is independent of the Windows app.

## Android automatic motion - 0.4.2 (build 6)

- Removed the Animations dropdown and app-level motion preference. Retained Flutter control transitions and the existing tab/theme transitions, with app motion automatically following Android accessibility preferences. System preference changes apply while the app is running.
- Existing appearance storage remains compatible: saved accent values load, legacy motion fields are ignored, and future saves contain only the accent. Paired-PC storage is unchanged.
- All 18 Flutter tests passed and Flutter analyze found no issues. Coverage verifies live system reduced-motion changes, removal of the dropdown, and loading an accent from legacy appearance data without retaining the motion field. Inspected the regenerated Settings preview.
- Built the debug APK from the source-synchronized temporary build directory, copied it to artifacts/mobile/TapMyPC-debug.apk, installed it in place, and reopened it. Installed package metadata confirms versionName=0.4.2 and versionCode=6.

## Desktop animations enabled - 0.3.2 (build 5)

- Removed the drawer-animation dropdown, saved motion field, Windows motion subscription, and presentation-level enable switches. Drawers, feedback fades, and the visible connection pulse now animate independently of Windows visual effects. Hidden/minimized or inactive connection indicators still have no animation clock.
- Existing appearance files keep their accent and ignore legacy Motion values. Changes to the accent save only the supported appearance field; network preferences, credentials, command behavior, and Android binaries are unaffected by this desktop patch.
- Release solution build passed with zero warnings/errors; all 46 .NET tests passed. An isolated WPF smoke harness verified legacy accent loading, accent-only persistence, animated drawer open/close, hit testing, and clock cleanup while Windows ClientAreaAnimation was False. It did not start the command host or invoke Windows operations.
- Published to artifacts/publish/TapMyPC-next. Both desktop and API DLLs reported file version 0.3.2.5 and product 0.3.2+5. The installed app was already closed, so tools/Apply-Update.ps1 -Launch applied the update and reopened it without stopping a running host. Installed metadata matched; UI Automation confirmed TAPMYPC v0.3.2 (build 5), an accent chooser, and no Drawer animations setting. The process reported responding.
- The accompanying Android UI changes remain 0.4.2 (build 6), previously installed and verified with 18 passing Flutter tests and clean analysis. The two app versions remain independent, with no API contract changes.

## Desktop shadow disabled - 0.3.3 (build 6)

- MainWindow no longer creates the custom transparent companion shadow window or its owner-move/size synchronization. The implementation is retained but inactive for this drag-performance comparison. Window content, animations, commands, and Windows visual-effects settings are unchanged.
- Release publish succeeded. Desktop and API DLLs both report product 0.3.3+6. The installed app was already closed; applied the staged release with tools/Apply-Update.ps1 -Launch and reopened it.
- UI Automation confirmed the visible v0.3.3 (build 6) heading. Native top-level window enumeration for the installed app process confirmed no TapMyPC shadow window exists. The app reported responding. Drag smoothness still needs the user's comparison; no performance improvement is claimed without that check.

## Desktop inactive connection badge - 0.3.4 (build 7)

- While listening without recent authenticated clients, the main status badge now says No phone connected and uses a neutral background, gray dot, and muted text. Connected clients retain the accent-colored Remote connected/count badge; stopping connections and waiting for a trusted network retain their distinct status labels. The existing ten-second presence policy is unchanged.
- Removed the unused WindowShadow implementation and its shadow-only native input helper. The desktop remains free of the transparent companion shadow; the user confirmed smoother dragging without it.
- Release publish succeeded, and staged desktop/API metadata both report file 0.3.4.7 and product 0.3.4+7. An isolated WPF presentation smoke check exercised idle, connected, and disconnect states across all five palettes; neutral idle and accent connected colors passed. Inspected the rendered idle card under artifacts/desktop-badge-check/idle.png. No real remote command was executed.
- After the user confirmed a normal tray exit, applied the staged update using tools/Apply-Update.ps1 -Launch and reopened the app. Installed desktop/API metadata both report 0.3.4+7. UI Automation confirmed the visible v0.3.4 (build 7) heading and connection badge; the process reported responding.

## HTTP monitor-list failure and misleading offline state - November 18, 2026

- Reproduced the failure on the running Android client: authenticated GET /monitors returned HTTP 500 while the desktop kept recording authenticated activity. Basic status worked; Android's combined status/device refresh discarded that success when any optional list failed.
- Found the deployment cause: tools/Apply-Update.ps1 copied only top-level publish files. Installed runtimes/win/lib/net10.0/System.Management.dll was absent, although the staged Windows runtime implementation was present (314632 bytes). The root-level assembly is not a substitute for that runtime asset.
- Fixed the updater to preserve relative directories when copying the entire publish tree, with destination containment checks and no deletion of existing files. Added tools/Test-Apply-Update.ps1 covering nested runtime/resource paths, spaces, replacement of old files, and preservation of other installation files; it passed.
- After the user's normal tray exit, reapplied the existing desktop 0.3.4 (build 7) package and reopened it. All 26 staged files matched installed hashes, including the runtime dependency. No desktop binary source or build settings changed for this packaging repair, so its version was retained. The existing Android app reconnected, with four audio outputs and one monitor loaded, before any mobile update was installed.
- Android 0.4.3 (build 7) now establishes connectivity after a verified status response; optional device-list failures clear only their affected list and show specific warnings. Failed lists retry using the existing ten-second polling cadence or manual refresh. Any authentication rejection still requires pairing, failed status still disables controls, and commands are never replayed. HTTP messages no longer retain the broken Http prefix.
- All 24 Flutter tests passed; analysis found no issues. New coverage exercises each optional list failing independently, credential revocation during list loading, unreachable status, and recovery through read-only retries. Debug APK build/install succeeded; installed metadata reports versionName=0.4.3 and versionCode=7.
- On the actual phone, UI Automation confirmed Connected to XAVIER, loaded sound status, monitor controls, and Bluetooth status without device-list errors. Desktop UI Automation confirmed its connected badge. Debugger attachment/forwarding used for request diagnosis was removed. No real power, display, audio, Bluetooth, or shortcut command was sent during diagnosis or verification; saved pairings were preserved.

## Documentation review before commit - November 18, 2026

- Audited current behavior docs against source and installed versions: desktop/API 0.3.4+7 and Android 0.4.3+7. Updated stale references to motion preferences, missing Flutter presentation, old Android screens, and a still-staged update. Earlier version-specific verification entries remain historical.
- Clarified the distinction between desktop authenticated-activity presence, successful mobile status, and optional device-list failures. Updated setup and versioning instructions to preserve the full published package, document the runtime-dependency repair and its copy regression check, and keep the version identity for repairs using unchanged published binaries.
- Checked 14 Markdown files for UTF-8/replacement characters and validated 52 relative documentation links and section anchors; all passed. The documentation-only audit does not require another app version or rebuild. Existing validation for this change set includes release publish and WPF badge checks, the updater regression check, 24 Flutter tests, clean Flutter analysis, and actual-device connection recovery.

## Certificate lifecycle validation — November 18, 2026

- The user reconsidered certificate lifecycle reliability as crucial and requested testing. Renewal/recovery is required follow-up work; no automatic renewal or local reset UI has been implemented or claimed as verified.
- Added three Windows-only lifecycle tests linked to the production HostCertificate source: approximately one-year validity, reopening the same identity, retaining its fingerprint across IP changes, missing-certificate failure, expired-certificate failure, and explicit replacement producing a different identity. Tests create uniquely named test-owned entries in the current-user Personal store and remove only those entries afterward; existing app certificates, identity.json, and paired-phone records are untouched.
- Added four Flutter tests using the actual PcApi against isolated loopback TLS servers. A valid pin permits a bearer-authenticated status request; a wrong/replacement identity, expired matching certificate, and not-yet-valid matching certificate receive no HTTP request or bearer credential. Explicitly pinning the replacement allows access. This verifies certificate trust acceptance after replacement, not a complete QR re-enrollment/reset flow.
- The committed TLS fixtures contain public test-only keys and certificates, never app credentials or production keys. They exercise real TLS sockets without changing the system clock or phone installation.
- All 49 .NET tests and 28 Flutter tests passed; Flutter analysis reported no issues. The Flutter checks ran from the existing temporary build copy because of Documents folder build restrictions. No real PC commands or running host changes were made. Only tests and documentation changed; app versions remain desktop 0.3.4+7 and Android 0.4.3+7.
## Certificate renewal and recovery — desktop 0.4.0+8 / Android 0.5.0+8

- Implemented automatic certificate renewal within 30 days of expiry and on restart after expiry, preserving the existing persisted RSA private key. identity.json advances only after a certificate is created. Missing certificates/private keys, future-dated certificates, or a missing identity reference with saved phones do not silently adopt a replacement identity.
- Android verifies the initial QR/manual leaf pin, derives its identity-key pin from the actual TLS peer, and saves optional keyPin in the existing protected profile. Valid same-key certificates preserve the bearer token; dates are still enforced. Legacy profiles migrate through a verified connection before renewal or require a fresh QR afterward. Discovery adds an untrusted pk hint; key changes never authorize control.
- Added desktop Advanced > Reset connection identity with explicit cancel/confirm. Confirmed recovery changes the key and persistently revokes all credentials/invitations. Active and paused recovery preserve pending timers and remembered connection preference. Android Settings > Re-pair selected PC replaces the deliberately selected profile while retaining other saved PCs.
- Release .NET tests: 53 passed. The certificate tests exercise actual current-user store operations using test-owned certificates and temporary settings, including same-key signing after renewal/reopen, expiry, missing/private-key-free certificates, missing identity references, clock errors, and persistent revocation.
- Flutter regression suite: 31 passed, including an enabled Windows/Flutter end-to-end fixture; analysis reported no issues. Real TLS socket checks verify expired/future certificates are rejected even when their key matches, and rejected identities receive no HTTP request/credential. Added discovery and protected-profile compatibility checks.
- Windows/Flutter end-to-end scenario passed: QR-secret enrollment, legacy profile migration, renewal/reconnect, listener restart, post-expiry renewal, simulated identity loss, explicit reset, old-key rejection, old-token HTTP 401, fresh QR enrollment/replay rejection, protected profile reload, and preservation of an unrelated PC profile.
- Native Android 16 integration passed on the connected device using the separate dev.tapmypc.tapmypc_mobile.certtest application ID. It ran the same scenario using real Android TLS/secure storage and then performed another reset/re-pair through the actual manual pairing UI. The connected dashboard and Re-pair selected PC route were verified. The test restores its prior profile/selection state; test-package absence and removal of the test adb reverse mappings were checked afterward. No normal app install/data reset was requested or performed.
- WPF smoke tool passed actual reset request/cancel/confirm bindings, active and paused reset, listener restart/resume, fresh QR generation, revocation, and timer preservation. Rendered and inspected artifacts/certificate-ui-check/confirmation.png. All controllers in these checks are simulated; no real power/audio/display/Bluetooth command was sent.
- Published desktop to artifacts/publish/TapMyPC-next; desktop and API metadata both report file 0.4.0.8/product 0.4.0+8. The staged package includes the nested Windows System.Management runtime dependency. Built the normal debug-signed Android APK at artifacts/mobile/TapMyPC-debug.apk; package inspection reports dev.tapmypc.tapmypc_mobile, versionName 0.5.0, versionCode 8. Both builds are staged, not applied to the normal installations. The previous installed versions in earlier records remain historical; current normal installation state was not reverified during this test.
- Browser certificate exceptions still require manual verification after renewal/reset. Updated Android must connect once before its first renewal to learn the key; an already-expired legacy leaf profile requires re-pairing. True private-key loss always requires local reset and enrollment. Long-term key rotation is explicit reset, not automatic identity replacement.
## Bluetooth secondary connection — desktop 0.5.0+9 / Android 0.6.0+10

- Implemented Windows encrypted/authenticated Classic RFCOMM forwarding to a fixed process-owned loopback HTTPS ApiHost. Native Android carries opaque TLS bytes to the existing Dart client. Both transports share certificate verification, bearer credentials, Core handlers, revocation, activity, presence, and PC-owned timers. No plaintext command adapter or arbitrary proxy destination was added.
- Authenticated status supplies Bluetooth address/service metadata. Android protects optional bluetoothAddress and per-PC Automatic/Wi-Fi-only/Bluetooth-only preference fields alongside existing identity pins. Only read-only connection recovery can fall back; authentication rejection does not fall back and no command is replayed. First enrollment/metadata learning remains on Wi-Fi.
- Verified the PC adapter supports Classic Bluetooth, BLE, and peripheral roles. Its radio was initially off; enabled it for the requested Bluetooth feature and left it on. RFCOMM service creation/advertising succeeded. The first physical TLS test exposed WinRT stream buffering; disabling adapter buffering delivered handshake/control messages immediately.
- All 54 .NET tests passed, including authentication protection for Bluetooth metadata. All 38 Flutter tests passed; the separate opt-in certificate end-to-end fixture was explicitly skipped in this regression invocation (its earlier checks remain above). Flutter analysis reported no issues. Added transport-preference/fallback/revocation/no-command-replay tests, protected profile compatibility, modal-read suspension, and an actual TLS concurrency check for optional list requests.
- Native Android 16 integration passed using separate dev.tapmypc.tapmypc_mobile.bttest package and the actual PC/phone radios. Setup/control endpoints were temporary loopback listeners with test-only secrets; Bluetooth data crossed RFCOMM. Verified pinned authenticated status, simulated mute, PC-owned timer scheduling/cancellation, wrong-identity rejection, automatic Bluetooth fallback after stopping the Wi-Fi API, a single media action without replay, listener restart/reconnect, transport choice persistence through the actual UI, and revocation returning 401. All mutating commands used simulated controllers, not the real PC.
- WPF smoke check with --bluetooth passed global startup, pause, identity-reset/restart, paused recovery/resume, fresh QR, revocation, and timer preservation with real Bluetooth listeners and simulated command controllers. Wider adapter/range/OS-pairing/background/sleep-resume coverage remains future manual testing.
- Published and applied desktop 0.5.0+9 only after confirming the installed host was closed. The updater preserved the complete publish tree. Installed desktop/API metadata both report 0.5.0+9; UI Automation confirmed the visible version, Bluetooth ready, connected badge, and responding process. No running real host was force-closed.
- Built and installed the normal Android 0.6.0+9 app with adb install -r. The normal app displayed onboarding, so completed a fresh manual enrollment using the locally displayed code and verified PC fingerprint, without clearing application data or revoking existing server clients. USB debugging briefly became unauthorized; the user approved it again before continuing.
- Real-app status over Bluetooth succeeded, but parallel optional list requests produced a shortcut-list warning. Android 0.6.0+10 serializes HTTP requests on one Bluetooth TLS/RFCOMM stream. Added a real TLS regression check asserting four parallel list reads share one connection and retain the original LAN/profile identity. Rebuilt/reinstalled in place; the saved PC/credential remained available. Package inspection and the installed UI report versionName 0.6.0/versionCode 10.
- On the normal installed app, verified Connected to XAVIER over Wi-Fi and Connected to XAVIER · Bluetooth, successful audio-output/monitor/shortcut lists without warnings, and the PC's active-remote badge. Captured and inspected artifacts/mobile/bluetooth-connected.png from build 10. These real-PC checks were read-only; no real audio/media/display/power/shortcut action was sent. Returned the saved connection mode to Automatic and verified Wi-Fi reconnection.
- Temporary test hosts stopped and their test adb reverse mappings were removed. Normal Android uses Nearby devices permission; no Bluetooth scan/location permission was added. No firewall, network-category, clock, or root certificate-trust settings were changed. The current APK is artifacts/mobile/TapMyPC-debug.apk, debug-signed as before; both normal apps are installed and running.
## Phone names, actual transport, and radio feedback — desktop 0.6.0+10 / Android 0.6.1+11

- Active desktop remote labels now include the phone name and transport from the API listener that authenticated its most recent request. Phone preferences or headers cannot spoof Wi-Fi/Bluetooth classification. Presence still expires after ten seconds and includes availability probes.
- Android reads the OS device name with model fallback, uses it for QR/manual enrollment, and reports it as bounded Base64-UTF8 metadata on authenticated requests. Existing pairings update their label without credential/identity changes. Invalid or unauthenticated hints cannot rename clients. Local Configure > Authorized phones > Phone name overrides persist and take precedence over reported names.
- Devices now shows PC Bluetooth: On/Off and only the applicable radio action over Wi-Fi. Unknown/unavailable/mixed states offer no guessed action. Actual Bluetooth connections disable the action and explain switching to Wi-Fi, including Automatic fallback. The dispatch guard checks actual transport before and after confirmation; the Bluetooth API listener also returns 422 before calling the radio controller.
- Release build passed with zero warnings/errors; all 59 .NET tests and 45 Flutter tests passed. The optional certificate fixture was explicitly skipped in the normal Flutter run. Flutter analysis reported no issues. Tests cover identity/transport migration, per-client isolation, customized-name persistence/precedence, invalid hints, optional storage failure, trusted listener classification, Bluetooth radio rejection, radio UI states, and native-name cleanup/fallback.
- Actual WPF smoke passed OS-name migration, switching displayed transport, local custom rename, and the existing reset/pause/timer checks. Native Android Bluetooth integration passed with the isolated test package: reported phone name and Bluetooth transport matched the host, radio writes returned 422 without simulated radio changes, and the actual Devices screen showed On with a disabled action. Existing encrypted connection/fallback/reconnect/revocation checks remained passing; only simulated PC controllers received test commands.
- Published/applied desktop 0.6.0+10 after confirming the normal host was closed. Installed the normal Android 0.6.1+11 APK with adb install -r; inspected package metadata and visible versions. The normal phone app showed onboarding after installation; completed fresh manual enrollment using locally displayed code/fingerprint without clearing data or revoking existing PC records. The cause of the missing local saved profile was not established; automated profile migration and isolated secure-storage tests passed.
- On the normal apps, verified POCO X6 5G · Wi-Fi and POCO X6 5G · Bluetooth on the desktop, and PC Bluetooth: On with the disabled Turn off action and switch-to-Wi-Fi explanation on the phone. Captured and visually inspected artifacts/mobile/radio-feedback-bluetooth.png. Returned the phone preference to Automatic. Live checks were read-only; no real radio/audio/media/display/power changes were sent.
- Installed desktop/API product versions are 0.6.0+10; normal APK identity is dev.tapmypc.tapmypc_mobile versionName 0.6.1/versionCode 11. Updates preserve the full desktop publish tree. Test hosts stopped and test adb reverse mappings were removed. Changes remain uncommitted for review.
## Android first-connection layout - 0.6.2 (build 12)

- Consolidated the separate logo, oversized tagline, description, and enrollment card into one compact setup card. The inline monitor icon and Connect your PC title share a row, two numbered steps explain initial Wi-Fi pairing, and Add your PC remains the sole enrollment action. The footer explains later Wi-Fi/Bluetooth reconnection. Actual storage/connection failures remain visible; the duplicate default getting-started message is omitted.
- The empty-state app bar keeps TapMyPC, help, and Settings without a version subtitle. Settings > About always retains installed version metadata, and the saved-PC dashboard keeps its version header. Existing QR/manual enrollment, certificate verification, and transport selection are unchanged.
- Refreshed local Flutter dependencies after the initial check found stale package configuration. Final analysis reported no issues; 46 Flutter tests passed and one certificate end-to-end test remained skipped because it requires its isolated fixture. UI coverage checks the enrollment callback, version access through About, and a 320-DIP screen at 1.8x text scale. Inspected normal and enlarged-text previews under artifacts/mobile-ui/welcome*.png.
- Built the debug APK from the synchronized C:/temp/TapMyPC-mobile-build copy and installed in place. Installed Android metadata confirms versionName=0.6.2 and versionCode=12. The phone already had a saved PC: verified its dashboard remained Connected to XAVIER and About showed the new version. Did not delete profiles to force native onboarding; the empty state was verified in rendered widget tests. No PC control commands were sent. Desktop package/version is unchanged.

## Laptop Wi-Fi wake investigation — November 18, 2026

- Identified Lenovo Legion 5 Pro 16ACH6H (82JQ), BIOS GKCN65WW, MT7921 Wi-Fi, disconnected Realtek Ethernet, S3 sleep/hibernate and AC power. The user enabled Wi-Fi wake authorization from Administrator PowerShell; it was verified armed.
- Advanced/NDIS wake settings were enabled, but the elevated network power-management probe reported magic/pattern wake Unsupported. Configuration alone does not establish working wake.
- The elevated awake receive probe verified exact 102-byte broadcast and unicast magic packets from the phone. Its temporary firewall rule was removed. Sleeping-station delivery remains unproven.
- The first approved sleep test failed; Windows attributed eventual resume to USB. The first traced resume also reported USB and possible shared input. The later hands-off test failed according to the user, with phone transmissions independently confirmed. The user also reported failure using Wolow with the laptop's verified Wi-Fi details.
- Lenovo documents Ethernet wake with AC power. No model-specific supported Wi-Fi wake setup/fix was found, and the user found no BIOS wake option. This is not manufacturer confirmation that every configuration is incapable.
- Closed laptop Wi-Fi wake investigation for the current configuration. Ethernet is impractical at the user's location and remains untested; laptop hibernate, shutdown, battery and Bluetooth wake remain untested. The user's desktop sleep/hibernate Wi-Fi wake success is separately user-reported.
- No app changes, rebuild or version bump. No permanent firewall, driver or firmware change was made; Wi-Fi wake authorization remains enabled, with the restore command documented. Latest application commit 821bd4f was pushed and its remote main SHA verified before investigation.
- Remote wake sending is not implemented. Hardware monitoring is next. Detailed evidence and limits are in [remote wake investigation](wake-investigation.md).

## Configurable Tailscale access — desktop 0.7.0+11 / Android 0.7.0+13

- Added explicit Tailscale adapter selection using interface metadata plus its default 100.64.0.0/10 IPv4 range. Automatic retains LAN behavior; unrelated CGNAT adapters do not gain a network-category exemption. The selected address is retained while unavailable and waits without LAN fallback. The listener still binds one selected address, keeps pinned HTTPS and credentials, and reports Tailscale presence independently of Bluetooth. No real network, firewall, Tailscale login, or installed app preference was changed.
- Android Settings > Connection > Change network address validates a numeric HTTPS URL and verifies the exact endpoint with the existing PC identity and credential before saving. Success selects Wi-Fi / Tailscale only and retains pins, token, name and Bluetooth metadata. Failed verification retains the old profile and visible feedback; commands are never retried.
- Release solution build succeeded with zero warnings/errors. All 72 .NET tests passed. New tests cover explicit/automatic/offline selection, address-range boundaries and interface identification. The existing certificate, pairing, Host/Origin and API tests passed.
- Flutter analysis reported no issues. All 50 Flutter tests passed; the opt-in production certificate fixture test was skipped because it requires its separate temporary host. Existing real TLS trust tests passed. New unit/widget checks cover URL validation, protected-profile compatibility, successful/rejected address editing, paused background reads and GET-only verification.
- WPF simulated-controller smoke passed listener lifecycle, identity confirmation/cancel/reset, saved pause, rename/presence and timer preservation. Rendered and visually inspected the Advanced settings panel with updated instructions. No real PC commands were sent.
- Published the full Windows update tree to artifacts/publish/TapMyPC-next. Desktop/API product metadata both report 0.7.0+11. Confirmed System.Management runtime assets are present. This update is staged, not applied.
- Built Android debug APK from the synchronized C:/temp/TapMyPC-mobile-build copy and copied it to artifacts/mobile/TapMyPC-0.7.0-build13.apk. Verified package dev.tapmypc.tapmypc_mobile, versionName 0.7.0 and versionCode 13 using aapt; checked edited source hashes match the build copy. The APK is built, not installed.
- Tailscale is installed on this PC with adapter metadata Name=Tailscale, Description=Tailscale Tunnel, matching the implementation. Its CLI reports no current Tailscale IPs (NoState), so actual tailnet binding/off-LAN phone reachability and firewall/policy checks remain unverified. Setup and single-address limits are documented in tailscale.md.

## Tailscale package delivery — November 18, 2026

- At the user's request, installed the existing Android 0.7.0+13 APK in place on the connected POCO phone using adb install -r. Installation succeeded; Android package metadata confirms dev.tapmypc.tapmypc_mobile versionName=0.7.0 and versionCode=13. No application data was cleared and no PC control commands were sent.
- Packaged the existing full Windows 0.7.0+11 publish tree as artifacts/releases/TapMyPC-0.7.0-build11-win-x64.zip. Verified all 26 files against archive entries by length and SHA-256, including nested runtime dependencies. Extract the ZIP and run TapMyPC-next/TapMyPC.exe with its companion files.
- Windows remains packaged/staged, not installed or launched by this delivery. No source/build settings changed and no additional version bump was needed.

## Unpacked PC build delivery - November 18, 2026

- Applied the existing 0.7.0+11 staged publish tree to artifacts/publish/TapMyPC with tools/Apply-Update.ps1 after confirming no TapMyPC process was running. Verified all 26 copied files by SHA-256 and desktop/API product versions. The executable is ready to run and was not launched.
- User requested old-build cleanup. Automatic approval review rejected deletion commands with blocked by policy, including the old publish directory, legacy APK and ZIP. No deletion occurred; staged files and archives remain. The supported copy-only update succeeded.


- Follow-up cleanup with individual non-recursive file removals succeeded for the obsolete TapMyPC-debug.apk and the ZIP. The 0.6.0 desktop binaries were replaced by the verified 0.7.0 build at the normal executable path. Cleanup of the duplicate TapMyPC-next staging tree remained blocked by automatic approval review; that duplicate remains.

## Rebuild after artifacts cleanup — November 18, 2026

- Rebuilt unchanged desktop 0.7.0+11 directly into artifacts/publish/TapMyPC with the retained local .NET SDK. Publish succeeded; no ZIP was created. No running TapMyPC process was present before publishing.
- Synchronized the repository Android source into C:/temp/TapMyPC-mobile-build and rebuilt the unchanged debug APK as 0.7.0+13. Recreated artifacts/mobile/TapMyPC-0.7.0-build13.apk and installed it in place on the connected phone with adb install -r.
- Source/build settings and version declarations are unchanged; the existing behavioral test results still apply. Rebuild and package checks were used for this recovery delivery.

## Independent local / Tailscale routes — desktop 0.8.0+12 / Android 0.8.0+14

- PC Configure > Remote access adds Allow access through Tailscale with an independent listener on the same configured port as LAN. Local Automatic excludes Tailscale. Both listeners share certificate identity, pairing, handlers, activity and timers; loss/disablement of either route does not stop the other. Stop connections still pauses all transports and persists.
- Authenticated status on LAN, Tailscale and Bluetooth includes additive networkConnection.localAddress/tailscaleAddress hints for currently listening routes. Android validates hints, stores separate last-known slots, and still verifies TLS identity before sending credentials to any address.
- Mobile offers Automatic (local, Tailscale, Bluetooth), Local network only, Tailscale only and Bluetooth only. Only read-only status recovers/switches connections. Automatic probes for a preferred network route on its ten-second cadence while using Tailscale/Bluetooth; an active Bluetooth stream is reused when no network route works. Commands never replay. The active route is visible; optional device-list errors still preserve verified connectivity.
- Address setup accepts a bare IP, carries over the known port, and puts port changes under Advanced. Exact-endpoint verification precedes saving without replacing the other route or selected preference. Legacy combined-network preferences migrate according to their saved IP; PC settings previously selecting Tailscale migrate to Automatic LAN plus Tailscale enabled. Pins, tokens, names, Bluetooth metadata and remembered pause are preserved.
- All 74 .NET tests passed. All 60 Flutter tests passed with the separate opt-in certificate fixture test skipped; final analysis reported no issues. Follow-up targeted radio/editor tests passed after wording updates. New checks cover route order, strict modes, revocation, Bluetooth stream reuse, address-slot preservation, legacy migration, hints, shared/advanced ports and small-screen/large-text setup.
- WPF simulated-controller checks passed independent simultaneous listeners, shared certificate identity, authenticated address hints, Tailscale toggle persistence, LAN loss/recovery and global stop, alongside identity reset/pause/timer checks. These dual-route tests use synthetic loopback adapter hints, not real Windows controls. Rendered and visually inspected the PC remote-access switch and Android enlarged-text editor.
- Tailscale is now active on the PC and an Android peer. An optional direct-Tailscale native integration test was prepared using a temporary simulated-control host and a separate Android application ID. Android rejected its installation with INSTALL_FAILED_USER_RESTRICTED (Install canceled by user), so that test did not run. The temporary host was stopped and its two adb reverse mappings removed. No firewall or tailnet policy was changed.
- Published desktop/API 0.8.0+12 unpacked to artifacts/publish/TapMyPC after confirming no normal host was running; checked compiled metadata and System.Management dependency. No ZIP was created and no real host was launched.
- The normal Android update was also rejected by Android with INSTALL_FAILED_USER_RESTRICTED. Requested the user unlock/allow USB installation before retrying. A read-only package query afterward reports no installed dev.tapmypc.tapmypc_mobile package; no uninstall or data-clear command was issued by this task. The APK is built, not installed. Desktop remains unpacked and ready, without a running normal host.
- Final Android package metadata is dev.tapmypc.tapmypc_mobile versionName=0.8.0, versionCode=14; saved at artifacts/mobile/TapMyPC-0.8.0-build14.apk. Checked edited app-source hashes against the build copy. LAN connection establishment uses a bounded three-second connection timeout while retaining the existing eight-second network request deadline and twenty-five-second Bluetooth deadline; targeted real-TLS tunnel, routing and refresh checks passed after this adjustment.

## Android installation retry — November 18, 2026

- After the user confirmed the phone was ready, retried adb install -r with the existing normal artifacts/mobile/TapMyPC-0.8.0-build14.apk. Installation succeeded.
- Verified installed dev.tapmypc.tapmypc_mobile metadata: versionName=0.8.0, versionCode=14. No uninstall, data clear, rebuild, version change or PC control command was performed. The earlier separate-package direct-Tailscale integration test remains unrun.

## Android Wake-on-LAN 0.9.0+15

November 19, 2026 (Asia/Taipei).

- Flutter analyzer reported no issues. The Flutter suite passed 61 tests and skipped the certificate end-to-end test, which requires its isolated Windows fixture. The new widget test verified validation, per-PC secure save and removal, the exact 102-byte payload and destination sent to the native bridge, and reconnection feedback without command replay.
- Built the debug APK at artifacts/mobile/TapMyPC-0.9.0-build15.apk. Verified package dev.tapmypc.tapmypc_mobile, version name 0.9.0, version code 15, and matching signing certificate for build 14. Installed as an in-place update on the connected phone, verified version name 0.9.0 and code 15 with ADB, and launched the app.
- Physical wake from sleep and hibernate in TapMyPC remains to be tested on the desktop that wakes with Wolow.

## Automatic Android Wake-on-LAN and Power controls

November 19, 2026 (Asia/Taipei).

- Windows 0.9.0+13 passed 82 .NET tests, including IPv4 broadcast calculation for multiple prefix lengths and authentication of wake hints. Published to artifacts/publish/TapMyPC-next and verified product metadata on both TapMyPC.exe and TapMyPC.Api.dll. The complete 22-file Windows x64 ZIP is at artifacts/publish/TapMyPC-0.9.0-build13-win-x64.zip. The Windows update is staged.
- Android 0.9.0+17 passed analysis and 61 Flutter tests. One certificate fixture test was skipped. The Wake-on-LAN test exercises the Power tab, automatic settings saved from status, precedence of an existing manual override, reversion to automatic, packet dispatch, and verified reconnect feedback. Verified APK and installed package metadata, and installed in place on the connected phone.
- On that phone, inspected the final Power screen and Wake-on-LAN editor by screenshot. Confirmed that Wake PC is visible before configuration and that all fields, the inline MAC error, Cancel and Save fit with the keyboard open. The phone retained its saved PC. No power action was sent during this visual check.
- Desktop hardware wake from sleep and hibernate still needs to be tested with the updated Windows host on the PC that wakes with Wolow.

## Android Wake-on-LAN layout 0.9.1+18

November 19, 2026 (Asia/Taipei).

- Compared both saved profiles on build 17. The newer host populated the editor and suppressed the extra setup shortcut in Power. The 0.8.0 host needed manual values and showed that shortcut. Settings > Wake-on-LAN opened for both.
- Verified Android package 0.9.1+18 after an in-place update. Inspected the final Power grid on the phone and opened the editor from Settings for both hosts. Both showed Wake PC in Power with no setup shortcut. The detected laptop settings and the manual editor for the older PC remained available. The phone displayed no Wolow wording.
- Flutter analysis reported no issues. The suite passed 61 tests and skipped the certificate fixture test. The wake regression verifies that Wake PC shares the Power action grid, settings remain reachable, and a saved profile sends the expected packet while offline.

## Android Power layout 0.9.2+19

November 19, 2026 (Asia/Taipei).

- Flutter analysis reported no issues. The suite passed 61 tests and skipped the certificate fixture test. The wake regression asserts the Power button order and the guidance shown for online and unconfigured PCs.
- Verified the APK and installed Android version 0.9.2, build 19 in place. Inspected the Power screen on the phone and confirmed the three button rows and the offline guidance while the selected PC was connected.

## Android Wake-on-LAN with a split-tunnel VPN 0.9.3+20

November 19, 2026 (Asia/Taipei).

- Compared the selected desktop profile on the phone with the working Wolow profile. The adapter MAC and broadcast destination matched. TapMyPC displayed a wake send failure after the reported sleep attempt. Android showed that the active Tailscale VPN included TapMyPC, disallowed explicit bypass, and advertised no route for the wake subnet. The pre-fix sender explicitly bound to the physical Wi-Fi network.
- Android now validates the Wi-Fi destination and uses system routing when the VPN leaves that destination on the LAN. Flutter analysis reported no issues and 61 tests passed, with the certificate fixture test skipped. Android built successfully, and ADB verified the in-place installation of 0.9.3 (build 20).
- A physical wake retest with build 20 is pending.

## Android offline feedback and settings navigation 0.9.4+21

November 19, 2026 (Asia/Taipei).

- Flutter analysis was clean. The suite passed 62 tests and skipped the certificate fixture test. Widget tests covered stable Offline status across retries, separate wake send and reconnect feedback, parent navigation, and exposing the Advanced port in both editors at large text size with keyboard insets. A failed address verification kept the entered draft and left the saved profile intact.
- Built and verified Android 0.9.4, build 21 and installed it in place on the connected phone. On the phone, Wake-on-LAN returned to Settings, both address editors returned to Connection, and Connection returned to Settings. The port field and both editor actions were visible with the keyboard open in both address editors.

## First-time Bluetooth setup and recovery after wake

November 19, 2026 (Asia/Taipei).

- With a fresh TapMyPC enrollment on the POCO X6 5G, verified authenticated status over Wi-Fi. On installed Android 0.9.4+21, selecting Bluetooth only while the PC and phone were unpaired reached an RFCOMM timeout before any pairing prompt appeared. A phone-side system pairing attempt also timed out at the Bluetooth link layer. Restored Automatic and verified local-network connectivity.
- On the user's repeat attempt with the installed builds, Android listed the laptop as bonded and returned its RFCOMM channel. Discovery for the unbonded desktop completed but returned no usable channel for TapMyPC's service UUID. The desktop connection failed before TapMyPC could authenticate. The trace does not establish whether bonding or the Windows service advertisement caused the missing channel.
- In a later installed-build sleep test, Windows woke at 11:58 a.m. and the desktop remained bonded on Android. The phone repeatedly logged `SDP_CFG_FAILED` before RFCOMM could open, even though Windows displayed Bluetooth ready. Cycling the TapMyPC Windows listeners alone left the next attempts failing. Relaunching TapMyPC on Android then produced successful service discovery and authenticated Bluetooth status on both devices using the existing bond. This recovery followed both steps, so the trace does not establish whether relaunch alone would have worked.
- Android 0.9.5+22 starts system pairing from Bluetooth only and waits for the bond before committing the route. Tests cover cancellation keeping the existing mode and a failed status connection being discarded before a fresh poll. Flutter analysis was clean. The suite passed 64 tests and skipped the opt-in certificate fixture.
- Windows 0.9.1+14 recreates the RFCOMM advertisement after system resume. All 82 .NET tests passed. Published to artifacts/publish/TapMyPC-next and applied after normal tray exit at the existing firewall-approved executable path. All 26 installed files matched the publish tree. Windows executable and API assembly metadata both report 0.9.1+14. Verified authenticated Bluetooth status on the existing phone profile after launch.
- In a second sleep/wake test with installed Windows 0.9.1+14 and Android 0.9.4+21, the Windows Bluetooth loopback listener reopened on a fresh port after wake. Android still logged `SDP_CFG_FAILED` repeatedly. The phone recovered about three minutes after wake, following a manual cycle of the Windows application listeners and a second Android relaunch. Authenticated Bluetooth status was verified on both devices. No system Bluetooth radio reset was performed. The observation does not establish which recovery step was necessary.
- With the desktop awake and connected, cycled Windows Bluetooth off and back on. The Windows listener opened on a new port, and Android discovered the RFCOMM channel and reconnected automatically using its saved pairing. The post-sleep failure had already cleared before this radio cycle.
- In a later sleep/wake reproduction, Android retained the desktop bond and retried Bluetooth discovery about every six seconds. The Windows 0.9.1+14 listener had already reopened after resume, but discovery kept returning `SDP_CFG_FAILED`. Cycling the Windows Bluetooth radio during the failure restored service discovery and opened RFCOMM within seconds, with both TapMyPC processes still running. This isolates the failure to the Bluetooth connection before HTTPS authentication and establishes the radio cycle as a recovery for this reproduction.
- Verified the Android package name and version 0.9.5+22 at artifacts/mobile/TapMyPC-0.9.5-build22.apk. The local debug signer differs from the installed app’s signer. Android canceled installation of a separate test package, so the usual app and its saved PC profiles remain on build 21. Physical verification of the Android changes remains pending.

## Windows connection card 0.9.2+15

- All 82 .NET tests passed. The isolated WPF smoke check verified the idle badge, the Bluetooth, Wi-Fi, and Tailscale badges, and a neutral border for mixed connections. It also checked that the host button follows the selected accent. Reviewed screenshots for each state.
- Published and applied build 15 after the previous Windows host exited. Verified all 26 installed files against the staged publish and checked version metadata on the executable and API assembly. The live dashboard showed the POCO phone name under a blue Bluetooth badge.

## Connection colors and power timing 0.10.0

- Windows 0.10.0+16 passed all 86 .NET tests. The isolated WPF check verified the checked preference switch track and thumb under the Amber theme. The authenticated API tests used a simulated device to verify zero-delay acceptance and dispatch, continued confirmation requirements, and the ten-second minimum for restart and shutdown.
- Published and applied Windows build 16 after the host exited. All 26 installed files matched the publish tree. The live UI showed both enabled preferences using the selected blue accent. No native power action was sent in verification.
- Android 0.10.0+23 passed analysis and 72 Flutter tests, with one opt-in certificate fixture skipped. Verified transport labels and colors, seconds and minutes input, short timer validation, direct zero-delay actions, older-host fallback, and the due card hiding offline. The debug APK at artifacts/mobile/TapMyPC-0.10.0-build23.apk uses a different signing key from build 21.
- With the user's approval, removed Android build 21 and installed build 23 under the standard package ID. ADB verified version 0.10.0, build 23 and a successful cold launch. The clean install starts at PC setup.

## Hardware monitoring 0.11.0

- Windows 0.11.0+17 passed all 87 .NET tests. An isolated pinned HTTPS host read 92 fresh metrics from the running PC Stats Tray at its configured one-second interval and rejected anonymous access. Applied the Windows update at the existing installation path, matched all 22 staged files by hash, verified desktop and API version metadata, and launched the host.
- Android 0.11.0+24 passed analysis and 73 Flutter tests, with the opt-in certificate fixture skipped. Tests verified the Stats tab, the default and expanded views, polling, and layout on a small screen with large text. The APK is at `artifacts/mobile/TapMyPC-0.11.0-build24.apk`.
- Android rejected the in-place update because the installed build 23 has a different signing certificate. Build 23 and its saved PCs stayed in place after that attempt.
- On the approved clean reinstall, the device removed build 23 and canceled the USB installation of build 24. Copied the APK to the phone Downloads folder and verified its SHA-256 hash. The user then completed the installation and confirmed Stats is working. ADB verified version 0.11.0 and build 24.

## Desktop hardware monitoring status 0.11.1

- Windows 0.11.1+18 passed all 87 .NET tests. An isolated WPF check with a loopback metrics fixture verified the card between Remote Access and Appearance, fresh and stale timestamps, unavailable guidance, recovery, and polling suspension when Configure was closed or the window minimized.
- Staged the 22-file Windows x64 publish tree in `artifacts/publish/TapMyPC-next` and verified desktop executable and API assembly metadata. The existing installation remains on 0.11.0+17.

## Desktop Configure order 0.11.2

- Windows 0.11.2+19 passed all 87 .NET tests. An isolated WPF check verified the order of the six sections, confirmed that Advanced Network & Security opens collapsed, and checked that the Hardware monitoring card scrolls into view in the compact drawer.
- Verified the Windows x64 desktop and API metadata and 22-file publish tree. Staged the build in `artifacts/publish/TapMyPC-next-0.11.2` because build 18 was running from `TapMyPC-next`.

## Desktop themes 0.12.0

- Windows 0.12.0+20 passed all 87 .NET tests and built with zero warnings. An isolated WPF check exercised all 25 theme and accent combinations, verified live updates across the window, tray menu and feedback banner, and confirmed that accent-only settings load as Dark with the saved accent.
- Staged the 22-file Windows x64 publish tree in `artifacts/publish/TapMyPC-next` and verified the desktop and API product versions.
