# Setup and operation

## Versions and QR visibility

Current development versions are Windows desktop/API **0.16.7 (build 34)** and Android **0.18.3 (build 47)**. Open **About TapMyPC** in the Windows **Configure** drawer or Android **Settings** to copy version information, read the setup guide, view third-party licenses, or open the GitHub repository. Android includes the connected PC host version when available. The phone learns wake settings from Windows 0.9.0 and newer and supports manual settings with earlier builds. See [verification](verification.md) for build and install history.

The desktop starts connections automatically on a Private/Domain network unless previously paused. The first QR appears automatically and hides after pairing. Use Add another phone for a new QR. Browser address and manual-code fallbacks are collapsed under optional details.

Desktop metadata is derived from `Version` and `BuildNumber` in `Directory.Build.props`; Android has its own declaration in `mobile/pubspec.yaml`. Follow [versioning guidelines](versioning.md) automatically for future deliverables. Version numbers need not match across the two apps when API compatibility is unchanged.

Android offers long-press actions and a configurable TapMyPC Controls widget on supported launchers. [Home-screen controls](../mobile/README.md#home-screen-controls)

## Phone names and connection feedback

The desktop connection card shows each active phone's name and its latest authenticated connection. Windows and Android use the theme text color for connection badge icons and labels. The badge background and outline identify Wi-Fi, Bluetooth, or Tailscale. Idle and offline badges use a disconnected icon. On Windows, phone names use the theme text color and the outer card border uses the accent. The network address and Bluetooth readiness lines describe the available listeners. Existing phones update their name on their next authenticated request after the Android update.

To customize a name, open Configure > Authorized phones, select the phone, edit Phone name, and select Save phone name. The override remains local to this PC and is not overwritten by the phone.

The mobile Devices tab shows PC Bluetooth: On/Off. Local network and Tailscale offer Turn off when on and Turn on when off. Bluetooth connections disable these changes with a switch-to-network message; unknown/unavailable/mixed states also prevent changes.

## Bluetooth secondary connection

Start connections on the PC with Bluetooth on. Connect Android over Wi-Fi once to save the verified PC’s Bluetooth address. In Android **Settings > Connection**, choose **Bluetooth only**, allow Nearby devices, and confirm the matching system code on both devices if prompted. TapMyPC keeps the previous connection mode if pairing fails. After setup, **Automatic** can use Bluetooth as a fallback. Windows re-advertises the Bluetooth service after waking when connections are enabled. See [Bluetooth setup and limitations](bluetooth.md).

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

Use a network you control for initial pairing. For access from another network or cellular, enable the optional Tailscale listener while the paired PC is awake. Hotspot and USB networking still need device testing. Do not expose the command port publicly or disable firewall protections as a workaround. [Tailscale setup](tailscale.md) · [Mobile connection limits](mobile-connections.md)

For Android **Stats**, update the Windows TapMyPC host and run PC Stats Tray 0.7.1 or newer. Select **Show Stats → Local apps** and keep the default port, 4587. [Hardware monitoring](monitoring-integration.md)

## Android Wake-on-LAN

1. Start the updated, paired PC app while the PC is awake. Select that PC in Android and wait for it to connect. TapMyPC saves the MAC and subnet broadcast address of the active local adapter with UDP port 9.
2. In **Settings > Wake-on-LAN**, check the detected values. Back returns to Settings. Manual values from an earlier build take priority. Edit the fields for a custom setup, or choose **Use automatic** to clear a manual override once the PC reports its settings.
3. Connect the phone to the PC’s local Wi-Fi, then put the PC to sleep. Wait for TapMyPC to show **Offline**, then open **Power** and tap **Wake PC**.
4. Confirm that the PC resumes and TapMyPC reconnects. Repeat from hibernate.

Wake PC is enabled when the selected PC is offline and has usable settings. The Power screen explains when the PC is still connected or needs wake settings. The wake button sends one UDP magic packet per tap. With a VPN active, the phone uses Android’s normal routing for destinations on the connected Wi-Fi subnet that the VPN leaves on the LAN. Once a connection attempt fails, the app shows **Offline**. After sending a packet it shows **Wake packet sent. Waiting for PC…** and reports the PC back online after an authenticated status response. The PC needs working network wake settings. The development laptop's Wi-Fi wake investigation is closed for its current configuration. See [wake investigation](wake-investigation.md).

## Remote Desktop preview

The Android viewer shows the physical Windows session, including a locked screen and the desktop after sign-in. It uses TapMyPC pairing over the current Wi-Fi or Tailscale route. Windows 0.13.0 and Android 0.12.0 are required. The device checks for sign-in after sleep or hibernate and for cellular performance are pending.

1. On Windows 0.15.2 or newer, select **Set up** on the **Remote Desktop** dashboard card, then **Set up Remote Desktop** in settings. Enter a viewer password or use **Generate password** to fill the field. **Show password** reveals the entry. Select **Continue**, then approve the Windows administrator prompt. On x64 Windows, TapMyPC checks the official UltraVNC downloads page for the latest stable version when the service is missing. Setup verifies the x64 installer’s published SHA-256 checksum, signing publisher, and version before running it. It then disables the installer’s inbound VNC firewall rules, configures the service for `127.0.0.1:5900`, and starts it. TapMyPC itself still runs from the extracted folder. TapMyPC installs silently and displays download progress and setup stages. **Copy** is available in its generated-password dialog. Repairing an existing service keeps its viewer password. [UltraVNC downloads](https://uvnc.com/downloads/ultravnc.html)
2. In TapMyPC on Windows, open **Configure → Authorized phones**, select the phone, and turn on **Allow Remote Desktop for this phone**. Existing pairings start with this permission off.
3. On Android, open **Power → Open desktop** while connected to the PC. Enter the UltraVNC password, optionally use **Show password** to verify it, and select **Remember for this PC** if you want the app to reuse it. Android saves it securely after a successful connection. To remove it or replace an older credential, open the viewer’s menu and select **Forget saved VNC password**. Enter your Windows sign-in credentials on the Windows screen if prompted.
4. Use the toolbar to type, rotate, play PC audio, or disconnect. Landscape hides Android's system bars and collapses the toolbar into a **Show viewer controls** button. An Android edge swipe reveals the system bars temporarily. Portrait restores the regular toolbar. **Remote Desktop options** includes **Fit**, **Fill**, stream settings, **Refresh screen**, and **Send Ctrl+Alt+Del**. Fit shows the entire desktop. The phone remembers Fit or Fill, and the viewer centers the image on open, when the display mode changes, and when the stream size changes. Use the horizontal or vertical scrollbar to pan any cropped area in Fill. Touching the desktop still controls Windows.
5. To try the viewer from outside the home network, use [Tailscale](tailscale.md) while the PC is running. The existing **Wake PC** action still sends a local Wi-Fi packet. Away-from-home wake depends on a separate always-on sender on the home network. The first viewer targets lock and resume of an existing session.

The Windows dashboard always shows the **Remote Desktop** card. It offers **Set up** until the local-only service is configured. After setup, it shows readiness and offers a **Settings** shortcut. **Connected** identifies the phone once Android 0.14.1 or newer reports successful VNC sign-in. Earlier phone versions can still stream.

Use the settings card to start, stop, or repair the service and reset the viewer password. For a reset, enter a custom password of 1–8 printable ASCII characters or generate one, then select **Save password**. **Max capture FPS** and **Keep wallpaper while connected** apply to this PC. **Diagnostics** shows the server version and listener status. Saving settings or resetting the password restarts a running capture service and disconnects the viewer. After changing the password, use **Forget saved VNC password** on a phone that saved the old one, then reconnect with the new password.

Setup downloads the installer to a temporary `C:\Program Files\TapMyPC-Setup-<random ID>\UltraVNC.exe` under the Windows Program Files folder. Setup cleans up the installer and the empty staging folder at the end. The installed server uses `C:\Program Files\uvnc\UltraVNC` and keeps its settings in `C:\ProgramData\UltraVNC\ultravnc.ini`.

Android requests a follow-up full frame one second after VNC sign-in. When authenticated PC status reports a Windows lock or unlock, the viewer requests a full frame immediately and again after one second. Use **Refresh screen** if black patches persist. See the [black-screen verification checklist](implementation-plan.md#deferred-black-patches-after-windows-unlock).

The options sheet reports the received stream resolution, screen receive rate and update rate. Expand **Stream details** for observed RFB encodings, JPEG chroma when a JPEG is received, and the audio format when available.

Choose **Save data**, **Balanced**, or **Sharper** to set JPEG quality and compression together, or adjust those levels independently in **Advanced stream settings**. The phone saves the preset and individual settings. Pick a preferred encoding, including lossless ZRLE. The viewer requests full color and shows JPEG and compression controls according to the selected encoding. Automatic and Tight use compression levels 1–9 for decoder compatibility. Zlib also accepts level 0. Tight color JPEG updates from UltraVNC 1.8.3.2 use 4:2:0 chroma. **Reset stream settings** saves Automatic encoding, Balanced quality, and Original resolution. **Server-side stream scale** requests a smaller framebuffer from UltraVNC without changing Windows display settings. Check **Stream resolution** for the actual size after the request or when reopening with the saved scale. If the new size is slow to confirm, the viewer requests a fresh frame. It reconnects at the saved scale if the resize stays pending and desktop updates stop. The screen receive rate varies with screen activity and encoding.

After an unexpected interruption of an established session, Android tries to reconnect in the foreground using the same pinned PC identity and saved stream settings. If it drops again immediately or sign-in fails during recovery, check the displayed reason. Recoverable failures offer **Reconnect** and **Reset stream settings and reconnect**.

### Play PC audio on Android

1. With Windows and Android 0.16.0 or newer, open **Configure → Authorized phones** on Windows, select the phone, and turn on **Allow Remote Desktop audio for this phone**. This permission is off for existing and new pairings until allowed on the PC.
2. Open the Android Remote Desktop viewer over Wi-Fi or Tailscale. In the viewer toolbar, tap **Play PC audio**. Audio starts off until you enable it for that PC. Android 0.17.5 and newer remember the choice and resume audio in future viewer sessions if the PC still grants permission. Use the phone’s media volume for its copy of the sound.

TapMyPC follows the default Windows playback output, including changes between devices during the session. The PC keeps its current playback device and volume. Apps routed exclusively to other outputs play there. Playback sharing stops when the toggle is turned off, the viewer closes, or permission is removed. The separate audio stream uses Opus stereo. Protected audio may be silent. [Windows loopback capture](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording)

For manual UltraVNC setup, use Windows service mode on `127.0.0.1:5900` with **Loopback Only**, **Password required**, and a separate VNC password. Disable the HTTP viewer, file transfer, and MS-Logon. Restart the service after saving a password change.

## HTTPS identity and certificates

The prototype creates an initial self-signed, one-year certificate in Current User / Personal, then persists its thumbprint in identity.json and reuses that exact certificate across address changes. Certificates renew automatically with the same identity key within 30 days of expiry, including recovery from expiry when that key is usable. A missing/unusable key fails closed and requires confirmed local identity reset and re-pairing. Its private key stays in the Windows user key store. No root certificate is trusted automatically, and the app does not run an HTTP fallback.

A phone browser will initially show a certificate warning. Before making a site-specific exception, verify that the address is the one displayed by the PC and compare the certificate's SHA-256 fingerprint with settings where the browser exposes it. Use Export public certificate if a trusted transfer or certificate inspection is needed; the exported `.cer` contains no private key. If the phone cannot verify the certificate identity, complete that setup separately rather than treating encryption alone as proof of identity. Do not broadly disable certificate validation.

Browser certificate inspection and exception controls vary. An IP change or certificate renewal may require a new browser exception. Verify the fingerprint on the PC before accepting it. Before sending credentials, Android verifies the exact certificate during enrollment and uses the saved certificate or verified identity-key pin on reconnection. [Certificate renewal and recovery](mobile-connections.md#certificate-renewal-and-recovery)

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
- All power actions require confirmation. With Windows 0.10.0 or newer, Android runs Lock, Sleep, and Hibernate immediately after confirmation. Older Windows hosts use the previous three-second countdown. Restart and Shut down keep a ten-second cancellation window.
- In Android **Power > Set a timer**, enter seconds or minutes and choose the action. The field starts at 30 minutes. Scheduled Lock, Sleep, and Hibernate accept 3 seconds to 24 hours. Scheduled Restart and Shut down accept 10 seconds to 24 hours. A timer stays visible while counting down offline and hides when due. The next authenticated status refresh supplies the current timer state.
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

The dashboard opens at 680 × 640 with bundled Inter typography, a frameless title bar, and minimize, maximize/restore, and hide-to-tray buttons. Sign-in startup and command notifications are on the main screen. Pair a Phone opens QR/manual setup; Activity opens command history; Configure shows Authorized phones, Remote access, Hardware monitoring, Quick launch shortcuts, Appearance, and the collapsed Advanced Network & Security section, in that order. Only one panel opens at a time; Escape, its close button, or the dimmed backdrop dismisses it. Newly generated QR invitations open the pairing panel automatically. The latest feedback appears on a smaller, wrapping line beneath the network address; pending-action cancellation remains on the main screen.

### Phone activity and PC notifications

The connection card shows a gray **No phone connected** badge while idle. When a phone is active, its name appears below a **Bluetooth**, **Wi-Fi**, or **Tailscale** badge. The badge backgrounds and outlines are blue, green, and purple respectively. The badge icon, label, and phone name use the theme text color. The card border uses the selected accent. The title-bar dot uses your theme accent and pulses while the dashboard is visible. Activity expires after ten seconds. Authenticated browser requests and phone availability checks also count. Stopping connections or revoking a client clears its presence.

Windows preference toggles use the selected theme accent when on. Android follows the same badge styling on its selected-PC card and uses a disconnected icon on the gray Offline badge.

The PC notification banner follows your desktop theme, accent, Inter font, and corner styling, with a brief fade on appearance. Failures remain red, and scheduled actions retain their countdown and Cancel action button. Notifications stay silent and do not activate or steal focus. The title-bar pulse stops while the dashboard is hidden/minimized, and notification suppression settings remain unchanged.

### Appearance and resizing

Configure > Appearance offers Dark, Light, Midnight, Forest, and Plum themes. Pick Blue, Mint, Purple, Teal, or Amber independently as the accent. The main window, tray menu, and PC notification banners update immediately. These choices are saved in `%LOCALAPPDATA%\TapMyPC\appearance.json`; network preferences and paired devices are independent. Drawer transitions, feedback fades, and the connection pulse animate independently of Windows visual effects. There is no separate animation setting, and legacy motion values are ignored. No Windows visual settings are changed.

Cards expand horizontally, up to a 1100-DIP dashboard width. At a window width of 1120 DIPs, essential preferences move beside the connection/pairing cards. Taller windows give panels and lists more usable space, while controls retain their natural height. Widgets have sharper corners; the outer frame remains rounded. The custom companion shadow is removed after the shadow-free version proved smoother to drag. This does not change Windows visual-effects settings.

The application uses explicit ClearType/Ideal text formatting and per-monitor DPI awareness. The system font configuration is not changed; assess the live rendering on your monitor at its normal scaling. The tray and executable use the bundled multi-resolution TapMyPC icon, and the tray menu uses the selected theme and accent, modestly rounded edges, and vertically centered Inter text. The font is loaded privately without installing it in Windows.

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

If you normally run TapMyPC from a versioned folder, pass that folder to `-InstallDirectory` so the update uses your existing executable path and firewall rule.

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

These are development builds. IPv6, a desktop installer, presets, a standalone remote touchpad or keyboard, display arrangement, iOS deployment, and Bluetooth peripheral management remain outside the current implementation. Keyboard and pointer input inside the Android Remote Desktop viewer are available in the preview. [Verification history](verification.md) · [Implementation plan](implementation-plan.md)

## Certificate lifecycle checks

Run dotnet run --project tools/TapMyPC.CertificateUiCheck -c Release for the isolated WPF confirmation/recovery check. It uses temporary settings, test-owned certificates, loopback HTTPS, and simulated controls.

For Windows/Flutter end-to-end checks, start dotnet run --project tools/TapMyPC.CertificateTestHost -c Release -- artifacts/certificate-test.json in the repository root. In a second shell run flutter test --dart-define=TEST_CERT_FIXTURE_PATH=ABSOLUTE_PATH_TO_FIXTURE from mobile (or its synchronized temporary build copy). The fixture must be fresh for each scenario run. Without that define, the fixture-specific test is explicitly skipped; the rest of the suite runs normally.

Afterward, read the fixture JSON in PowerShell and POST to its controlUrl + /test/stop with the X-Test-Key header set to its controlKey. This lets the helper remove its own certificates and temporary settings. Never point this harness at the real app. Its control listener is loopback-only, requires a fresh test-only secret, and has no real Windows command controller.

For native testing, mobile/integration_test/certificate_lifecycle_test.dart takes TEST_CERT_FIXTURE as the base64-encoded fixture JSON through a temporary --dart-define-from-file file. Use a separate temporary Android applicationId, forward only the fixture API/control loopback ports with adb reverse, then remove those mappings. The test restores protected profiles/selection in its test app. Fixtures contain temporary test credentials and belong under ignored artifacts, never in normal APK build defines. Test certificate fixtures under mobile/test/fixtures contain public test-only keys, not live identities.
