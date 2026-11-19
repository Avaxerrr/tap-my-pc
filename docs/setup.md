# Setup and operation

## Versions and QR visibility

Built versions: desktop/server **0.8.0, build 12** is unpacked at artifacts/publish/TapMyPC; Android **0.8.0, build 14** is installed on the connected phone. Both add independent LAN/Tailscale access and four phone connection choices. See [Tailscale setup](tailscale.md) and verification.md for delivery status. Previous versions: desktop/server **0.7.0, build 11** is applied at artifacts/publish/TapMyPC, and Android **0.7.0, build 13** is installed on the connected phone. These add optional [Tailscale remote access](tailscale.md). Build/staging status is recorded in verification.md. Previously installed development versions: desktop/server **0.6.0, build 10** (status reports `serverVersion: 0.6.0+10`) and Android **0.6.2, build 12**. Installation results are recorded in verification.md. Its connected-dashboard header and Settings > About read installed package metadata; the first-connection header omits the version for a cleaner layout; its version is independent of the PC version.

The desktop starts connections automatically on a Private/Domain network unless previously paused. The first QR appears automatically and hides after pairing. Use Add another phone for a new QR. Browser address and manual-code fallbacks are collapsed under optional details.

Desktop metadata is derived from `Version` and `BuildNumber` in `Directory.Build.props`; Android has its own declaration in `mobile/pubspec.yaml`. Follow [versioning guidelines](versioning.md) automatically for future deliverables. Version numbers need not match across the two apps when API compatibility is unchanged.

## Phone names and connection feedback

The desktop's active remote line shows the phone name and actual connection, for example POCO X6 5G · Bluetooth. Wi-Fi address and Bluetooth ready describe listener availability separately. Existing phones update their name on their next authenticated request after the Android update.

To customize a name, open Configure > Authorized phones, select the phone, edit Phone name, and select Save phone name. The override remains local to this PC and is not overwritten by the phone.

The mobile Devices tab shows PC Bluetooth: On/Off. Local network and Tailscale offer Turn off when on and Turn on when off. Bluetooth connections disable these changes with a switch-to-network message; unknown/unavailable/mixed states also prevent changes.

## Bluetooth secondary connection

Start connections on the PC with Bluetooth on. Connect Android over Wi-Fi once to save the verified PC's Bluetooth metadata. In Android Settings > Connection choose Automatic, Local network only, Tailscale only, or Bluetooth only; allow Nearby devices and complete OS pairing if prompted. Saved phones can then control without a reachable LAN. Start/Stop connections controls both transports; Public LAN restrictions do not disable Bluetooth. See [Bluetooth setup and limitations](bluetooth.md).

## Certificate renewal and recovery

Certificates renew automatically within 30 days of expiry using the same PC identity key. An expired certificate can also renew when its private key remains available. Install/update Android first and let it connect once to learn the key before updating a PC whose certificate is near expiry; old leaf-only profiles otherwise require a fresh QR after renewal.

For a missing/unusable PC key, open Configure > Advanced Network & Security > Reset connection identity and confirm Reset and revoke all phones. All phones must pair again. Pending timers, shortcuts, preferences, and the remembered Start/Stop choice remain. On Android select that PC and use Settings > Re-pair selected PC, then scan/confirm the new QR or use its new manual fingerprint/code. Other saved PC profiles remain.

Reset also works while connections are paused. If the network is unavailable/untrusted, reconnect to a trusted network and start connections before pairing. Check an incorrect PC/phone clock before resetting: certificates outside their validity dates are rejected. Browsers need a new manually verified self-signed certificate exception after renewal/reset. See [connection trust and migration](mobile-connections.md#certificate-renewal-and-recovery).

## Build and launch

Development requires Windows and the .NET 10 SDK. The repository pins SDK 10.0.115 with patch roll-forward. NuGet restores QR rendering and mDNS support along with test dependencies.

```powershell
dotnet build TapMyPC.sln -c Release -m:1
dotnet test TapMyPC.sln -c Release -m:1
dotnet run --project src/TapMyPC.Desktop -c Release
```

Normal launch resumes the remembered connection preference (enabled by default). Stop connections persists a pause across launches; Start connections resumes it. Closing the settings window hides it; the app stays in the tray. Double-click the tray icon or use Settings to reopen it. Exit from its tray menu stops the listener and cancels all pending timers. A second instance exits rather than creating another listener.

## Connect a phone

1. Use the same trusted home network on the phone and PC. Internet access is unnecessary. Guest networks or router client isolation may prevent connection.
2. The dashboard automatically detects an active private IPv4 address, preferring a gateway-capable adapter and then Wi-Fi. Use Advanced settings only to override it. `127.0.0.1` is available there for debugging and works only on the PC itself. If no network address exists, the app explains the problem instead of silently falling back to localhost.
3. Connections start automatically on trusted Windows Private/Domain networks, unless previously paused. Select Start connections to resume. The initial port is 45831 and the local listener binds only to the selected LAN address; the separate Tailscale opt-in adds its adapter on the same port.
4. Complete the HTTPS identity check below and any required local firewall setup.
5. Open the displayed HTTPS URL on the phone, generate a pairing code on the PC, and enter it with a device name on the phone. Commands show sending/result notifications; pending power actions have a visible countdown and cancellation on both devices.

Address selection is refreshed on network changes and every ten seconds. The listener restarts automatically on the selected trusted address while enabled; it stops on an untrusted network. A deliberate Stop connections remains paused. Old settings from the first prototype migrate to Automatic selection; new explicit debugging overrides are retained.

Codes last five minutes, accept one successful pairing, and close after five incorrect attempts. Generate another code for each additional phone. Up to 20 clients may be paired. A successful pairing stores a long-lived credential in that browser's local storage. Private browsing or clearing site data loses it.

Select a paired device on the PC and revoke it to invalidate its credential immediately. Forget this connection on the website removes only that browser's saved copy; it does not revoke a credential that has been copied elsewhere.

## Pair the Android app with QR

1. Open the desktop app on a trusted network. Resume Start connections if previously paused.
2. The initial QR appears automatically when no phones are paired. For an additional phone select Add another phone. The QR and browser fallback code expire after five minutes and permit one successful pairing.
3. On Android select Add PC, then Scan PC QR. Allow camera access when Android asks.
4. Scan the QR displayed by your PC, review its name/address, and select Pair with this PC. The app verifies the embedded certificate fingerprint before sending its one-time secret.
5. The QR hides after pairing. Android saves the credential securely, discovers saved PCs, verifies the certificate, and reconnects automatically. Use the PC selector to choose another independently paired PC; the selection is remembered.

Manual setup remains under Enter details manually. If camera access is denied, enable it in Android settings or use manual setup. Regenerate on the PC if a QR expires or was used. Stopping the host closes outstanding invitations. Ordinary saved-address reconnects do not require a new QR.

## Automatic reconnection and isolated networks

Android QR enrollment, saved PC selection, native mDNS discovery, certificate reuse across IP changes, and remembered connection startup are implemented. The browser continues using its existing manual code flow. Existing pairings already create persistent credentials; ordinary reconnects do not inherently require a new code.

Public/guest Wi-Fi may allow internet while blocking direct phone-to-PC traffic through AP/client isolation. Saved credentials, QR scanning, or a correct IP cannot override that block. If only discovery is blocked, a reachable direct address may work. A timeout alone does not identify isolation conclusively.

Use a network you control for initial LAN operation. Hotspot/USB networking require device tests. VPN/relay support is future work and needs a permitted route. Do not expose the command port publicly or disable firewall protections as a workaround. See [mobile connections](mobile-connections.md).

Hardware monitoring is the next implementation. Laptop Wi-Fi wake testing is closed for the current configuration; remote wake sending remains unimplemented. See [wake investigation](wake-investigation.md). The monitoring bridge preserves the standalone collector and website; see [monitoring integration](monitoring-integration.md).

## HTTPS identity and certificates

The prototype creates an initial self-signed, one-year certificate in Current User / Personal, then persists its thumbprint in identity.json and reuses that exact certificate across address changes. Certificates renew automatically with the same identity key within 30 days of expiry, including recovery from expiry when that key is usable. A missing/unusable key fails closed and requires confirmed local identity reset and re-pairing. Its private key stays in the Windows user key store. No root certificate is trusted automatically, and the app does not run an HTTP fallback.

A phone browser will initially show a certificate warning. Before making a site-specific exception, verify that the address is the one displayed by the PC and compare the certificate's SHA-256 fingerprint with settings where the browser exposes it. Use Export public certificate if a trusted transfer or certificate inspection is needed; the exported `.cer` contains no private key. If the phone cannot verify the certificate identity, complete that setup separately rather than treating encryption alone as proof of identity. Do not broadly disable certificate validation.

Browser certificate inspection/exception controls differ, and this is a prototype setup friction. The Android client verifies an exact QR/saved certificate pin before sending credentials, including after address recovery. An IP change or certificate renewal may require a new browser exception; confirm the new identity on the PC.

## Windows Firewall

The app does not automatically create firewall rules, request elevation, or change the network profile. Localhost testing needs no inbound LAN rule. If the phone cannot connect, check the selected address and network isolation before adding a rule. Automatic discovery uses mDNS UDP 5353 on the selected trusted adapter; if blocked, saved/direct addresses remain usable when TCP is reachable. The app does not open that firewall port automatically.

On a trusted home network configured as Private, allow the published executable's TCP port for the Private profile and LocalSubnet only. This example is for a user to run in an elevated PowerShell when ready; it has not been run by the agent:

```powershell
$remoteExecutable = (Resolve-Path '.\artifacts\publish\TapMyPC\TapMyPC.exe').Path
New-NetFirewallRule -DisplayName 'TapMyPC - home network' -Direction Inbound -Action Allow -Program $remoteExecutable -Protocol TCP -LocalPort 45831 -Profile Private -RemoteAddress LocalSubnet
```

Scope LocalAddress to the chosen Wi-Fi address as well if desired. Update the rule if the executable location or port changes. Do not open router ports or add a Public-profile rule for this prototype.

## Timers and controls

- Volume is 0–100; mute uses an explicit true/false state.
- Volume up/down buttons send standard Windows volume keys, requesting the native system overlay where Windows displays it. Step size and overlay visibility are controlled by Windows; they are not fixed five-percent operations. Slider/mute changes retain direct, explicit state setting. Volume adjustments do not show a custom PC notification; slider changes may not display a native flyout. Mute/unmute and errors still show compact custom feedback. Phone feedback and dashboard activity are retained for every action.
- Media commands send standard Windows media keys. The active media application decides how to handle them. Current track metadata is not implemented.
- Display-off affects connected monitors through the Windows display-power message. Input/activity may wake them.
- All power actions require confirmation. Shutdown/restart use a minimum ten-second cancellable delay; lock/sleep/hibernate use a minimum three seconds.
- Silent TapMyPC notifications show remote activity without activating the window. The final ten seconds of a pending power action show a cancel button. The main-screen Show command notifications switch can disable these custom notifications. This does not disable Windows' own media/volume overlays. Exclusive-fullscreen visibility still needs manual verification.
- There is one pending power action. Cancel it before scheduling a different one. The timer runs on the PC after browser disconnection and after stopping the API listener.
- Exiting the process cancels the timer. Timers are not persisted, do not wake a sleeping PC, and cannot be canceled once execution begins.
- Shutdown/restart never pass `/f`. Windows or unsaved work may block the transition. Sleep/hibernate use the existing user shutdown privilege, enabled temporarily during execution; no elevation prompt is requested.

## Audio outputs, shortcuts, and monitors

On Android, open Remote > Sound and tap the audio-output button, then choose a device in the Audio output sheet. The browser remote uses its output selector and Use output button. This changes Windows default playback and communications roles; apps pinned to a specific device may keep using it. Unplugged/disconnected outputs are rejected. The isolated Windows adapter uses the IPolicyConfig compatibility interface, which is not a documented public Windows API; Windows updates may affect switching, and failures are surfaced.

In the PC app, open Configure > Quick launch shortcuts. Enter a name, then select Choose local app or .lnk, or enter an http(s) website and select Add URL. Only locally approved entries appear on the phone. Remove an entry on the PC to reject future launches by its ID. Application arguments can be configured in a locally approved .lnk file; no remote command-line input is accepted. Shortcuts are saved in %LOCALAPPDATA%\TapMyPC\shortcuts.json. Missing applications produce an error when launched.

On Android, the Devices tab shows each display's brightness slider and power buttons. Unsupported controls are disabled with an explanation. Built-in brightness uses Windows WMI when supported; external monitors use DDC/CI, which may need enabling in the monitor's physical menu. Adapters, docks, drivers, HDR modes, and monitor firmware can affect support. All-monitors-off remains available separately.

Individual off requests use DDC power-saving mode. Some monitors stop accepting DDC commands or disappear from Windows while off and require their physical button to wake; the UI reports an unreachable display rather than claiming it can turn it on. Commands report a request, and device refresh reads back the available state.

On Android, use Settings > Refresh devices or pull to refresh after plugging/unplugging devices or editing shortcuts. Lists also refresh on connection and after commands. Output, monitor, and shortcut lists are separate from the two-second status poll; failed list reads retry on the existing ten-second foreground cadence.

## Bluetooth on/off

The phone remote has a Bluetooth card showing On, Off, Mixed, Disabled, or Unavailable, plus explicit Turn on / Turn off buttons. It controls the PC's Bluetooth radios over the existing Wi-Fi connection. Turning it off disconnects Bluetooth peripherals; confirm before sending that request. It never changes Wi-Fi or disables devices through Device Manager.

The first change may require Windows consent on the PC. Missing adapters, disabled radios, or rejected access are reported without blocking other remote controls. Status reads do not request permission. A command accepted by Windows may still be transitioning; the remote refreshes the effective state.

These controls change radio power. The separate phone-to-PC Bluetooth transport is implemented; turning off the PC radio will disconnect it. Bluetooth peripheral management remains unimplemented. See [Bluetooth setup](bluetooth.md).

## Startup and local data

Startup is off by default. The checkbox writes a per-user Run entry that launches the current executable with `--tray`. This mode respects the saved connection preference and keeps the window hidden; a paused host stays paused. Use a stable published executable path before enabling startup. Remove the checkbox before moving/deleting that executable.

Host preferences and paired-client hashes live in `%LOCALAPPDATA%\TapMyPC\host.json` and `devices.json`. The same directory contains `identity.json` with the public certificate thumbprint reference. Certificate keys are stored separately in the Windows user certificate/key stores. Do not edit these files while the app is running. Corrupt or inaccessible configuration is reported rather than silently discarded.

The dashboard opens at 680 × 640 with bundled Inter typography, a frameless title bar, and minimize, maximize/restore, and hide-to-tray buttons. Sign-in startup and command notifications are on the main screen. Pair a Phone opens QR/manual setup; Activity opens command history; Configure contains shortcuts, paired devices, and Advanced Network & Security. Only one panel opens at a time; Escape, its close button, or the dimmed backdrop dismisses it. Newly generated QR invitations open the pairing panel automatically. The latest feedback appears on a smaller, wrapping line beneath the network address; pending-action cancellation remains on the main screen.

### Phone activity and PC notifications

The connection card shows a muted No phone connected badge while listening without an active remote. It switches to an accent-colored Remote connected badge and client names after authenticated activity. The title-bar dot changes to your accent and gently pulses while the dashboard is visible. After ten seconds without activity it returns to idle; stored pairings alone are not treated as connected. Browser requests and phone availability checks count, so the indicator does not imply that this PC is selected on the phone. Stopping connections or revoking a client clears its presence.

The PC notification banner follows your desktop accent, Inter font, and corner styling, with a brief fade on appearance. Failures remain red, and scheduled actions retain their countdown and Cancel action button. Notifications stay silent and do not activate or steal focus. The title-bar pulse stops while the dashboard is hidden/minimized, and notification suppression settings remain unchanged.

### Appearance and resizing

Configure > Appearance offers Blue, Mint, Purple, Teal, and Amber accents. Changes preview immediately and are saved in `%LOCALAPPDATA%\TapMyPC\appearance.json`; network preferences and paired devices are independent. Drawer transitions, feedback fades, and the connection pulse animate independently of Windows visual effects. There is no separate animation setting, and legacy motion values are ignored. No Windows visual settings are changed.

Cards expand horizontally, up to a 1100-DIP dashboard width. At a window width of 1120 DIPs, essential preferences move beside the connection/pairing cards. Taller windows give panels and lists more usable space, while controls retain their natural height. Widgets have sharper corners; the outer frame remains rounded. The custom companion shadow is removed after the shadow-free version proved smoother to drag. This does not change Windows visual-effects settings.

The application uses explicit ClearType/Ideal text formatting and per-monitor DPI awareness. The system font configuration is not changed; assess the live rendering on your monitor at its normal scaling. The tray and executable use the bundled multi-resolution TapMyPC icon, and the tray menu uses dark surfaces with the selected accent, modestly rounded edges, and vertically centered Inter text. The font is loaded privately without installing it in Windows.

### Upgrade from PC Remote

The application is now named TapMyPC and launches as `TapMyPC.exe`. It reads legacy `%LOCALAPPDATA%\PCRemote` preferences and paired-client records if the corresponding new TapMyPC files do not exist. New writes use `%LOCALAPPDATA%\TapMyPC`. Existing browser credentials migrate to the new local-storage name on page reload, and valid legacy certificates are reused to preserve server identity.

Exit the old PC Remote instance before opening TapMyPC; both versions share an instance lock to prevent conflicting listeners and timers. If sign-in startup was already enabled, launching TapMyPC migrates that existing opt-in to its current executable path. No startup entry is created for users who had not enabled it. The new executable name/path may require updating a program-scoped firewall rule; no rule is changed automatically.

## Publish

```powershell
dotnet publish src/TapMyPC.Desktop -c Release -r win-x64 --self-contained false -o artifacts/publish/TapMyPC
```

Run `TapMyPC.exe` from that folder. Keep its companion files together. This is a folder deployment, not an installer, and requires both .NET 10 Windows Desktop and ASP.NET Core runtimes on the target PC. The development machine already has them.

## Update integrity checks

The update script copies the complete publish tree, including nested runtime libraries, while preserving existing installation files and per-user settings. Run `tools/Test-Apply-Update.ps1` for the isolated copy regression check. Preserve the paths produced by publish: a runtime-specific publish can place dependencies at the root, while a portable publish can include nested runtime assets. In the repaired portable installation, missing `runtimes/win/lib/net10.0/System.Management.dll` caused monitor enumeration to fail even though authentication and basic status succeeded. Do not copy only the top-level files of a publish that includes subdirectories.

Android keeps the PC connected when status succeeds but a device list fails. The affected section shows a warning and retries its read on the existing ten-second cadence or on manual refresh. Credentials rejected by any request still require pairing.

## Apply a staged update

When the existing published app is running, build the next version separately:

```powershell
dotnet publish src/TapMyPC.Desktop -c Release -r win-x64 --self-contained false -o artifacts/publish/TapMyPC-next
```

Exit the old app using its tray menu when convenient; pending timers will be canceled. Then, from the repository directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Apply-Update.ps1
```

Open the usual `artifacts/publish/TapMyPC/TapMyPC.exe` afterward, then resume connections if paused and reopen the phone app/page. The script refuses to update a running copy. It copies staged files into the existing location, leaves user preferences/paired devices untouched, and preserves the executable path used by startup and program-scoped firewall rules. It does not kill the old host, change firewall settings, or run PC controls. Optional `-Launch` starts the updated executable after copying.

## Simulator

```powershell
dotnet run --project tools/TapMyPC.Simulator -c Release
```

The simulator binds only to `https://127.0.0.1:45832`, prints a one-time pairing code, and uses memory-only audio/state plus simulated power/media/display actions. It has no dependency on the Windows control project. Restart it for a fresh pairing code or after code expiry. Stop with Ctrl+C. Credentials/settings do not survive simulator restart.

For headless browser verification using installed Chrome:

```powershell
npm install --prefix artifacts/browser-qa --no-save --package-lock=false playwright@1.65.1
node tools/browser-smoke.cjs <code-printed-by-simulator>
```

This script targets only the simulator port, uses an isolated browser profile, and writes screenshots under `artifacts/screenshots`. Its certificate-validation exception is test-only for the ephemeral localhost simulator. Set `TAPMYPC_CHROME` to an alternative Chromium executable if necessary.

## Remaining limitations

The user has confirmed phone Wi-Fi connectivity. Certificate trust, native mutating controls, interactive tray behavior, and sign-in startup still require further verification. IPv6, a desktop installer, presets (deferred), remote input (deferred), display arrangement, iOS deployment, Bluetooth peripheral management, and remote wake are not implemented. The current build is a prototype, not a verified production release.

## Certificate lifecycle checks

Run dotnet run --project tools/TapMyPC.CertificateUiCheck -c Release for the isolated WPF confirmation/recovery check. It uses temporary settings, test-owned certificates, loopback HTTPS, and simulated controls.

For Windows/Flutter end-to-end checks, start dotnet run --project tools/TapMyPC.CertificateTestHost -c Release -- artifacts/certificate-test.json in the repository root. In a second shell run flutter test --dart-define=TEST_CERT_FIXTURE_PATH=ABSOLUTE_PATH_TO_FIXTURE from mobile (or its synchronized temporary build copy). The fixture must be fresh for each scenario run. Without that define, the fixture-specific test is explicitly skipped; the rest of the suite runs normally.

Afterward, read the fixture JSON in PowerShell and POST to its controlUrl + /test/stop with the X-Test-Key header set to its controlKey. This lets the helper remove its own certificates and temporary settings. Never point this harness at the real app. Its control listener is loopback-only, requires a fresh test-only secret, and has no real Windows command controller.

For native testing, mobile/integration_test/certificate_lifecycle_test.dart takes TEST_CERT_FIXTURE as the base64-encoded fixture JSON through a temporary --dart-define-from-file file. Use a separate temporary Android applicationId, forward only the fixture API/control loopback ports with adb reverse, then remove those mappings. The test restores protected profiles/selection in its test app. Fixtures contain temporary test credentials and belong under ignored artifacts, never in normal APK build defines. Test certificate fixtures under mobile/test/fixtures contain public test-only keys, not live identities.