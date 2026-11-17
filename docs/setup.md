# Setup and operation

## Build and launch

Development requires Windows and the .NET 10 SDK. The repository pins SDK 10.0.115 with patch roll-forward. No third-party runtime package is needed by the application; test packages restore from NuGet.

```powershell
dotnet build TapMyPC.sln -c Release -m:1
dotnet test TapMyPC.sln -c Release -m:1
dotnet run --project src/TapMyPC.Desktop -c Release
```

Normal launch opens settings with the network listener stopped. Closing the settings window hides it; the app stays in the tray. Double-click the tray icon or use Settings to reopen it. Exit from its tray menu stops the listener and cancels all pending timers. A second instance exits rather than creating another listener.

## Connect a phone

1. Use the same trusted home network on the phone and PC. Internet access is unnecessary. Guest networks or router client isolation may prevent connection.
2. The dashboard automatically detects an active private IPv4 address, preferring a gateway-capable adapter and then Wi-Fi. Use Advanced settings only to override it. `127.0.0.1` is available there for debugging and works only on the PC itself. If no network address exists, the app explains the problem instead of silently falling back to localhost.
3. Click Start secure host. The initial port is 45831. The listener binds only to the selected address.
4. Complete the HTTPS identity check below and any required local firewall setup.
5. Open the displayed HTTPS URL on the phone, generate a pairing code on the PC, and enter it with a device name on the phone. Commands show sending/result notifications; pending power actions have a visible countdown and cancellation on both devices.

Address selection is refreshed when starting the host or using Advanced / Refresh. It does not migrate a running listener automatically when the network changes. Stop/start the host to use a new address. Old settings from the first prototype migrate to Automatic selection; new explicit debugging overrides are retained.

Codes last five minutes, accept one successful pairing, and close after five incorrect attempts. Generate another code for each additional phone. Up to 20 clients may be paired. A successful pairing stores a long-lived credential in that browser's local storage. Private browsing or clearing site data loses it.

Select a paired device on the PC and revoke it to invalidate its credential immediately. Forget this connection on the website removes only that browser's saved copy; it does not revoke a credential that has been copied elsewhere.

## Planned mobile flow and isolated networks

QR enrollment, automatic discovery, mobile PC profiles, and remembered host startup are planned, not current browser features. Existing pairings already create persistent credentials; ordinary reconnects do not inherently require a new code.

Public/guest Wi-Fi may allow internet while blocking direct phone-to-PC traffic through AP/client isolation. Saved credentials, QR scanning, or a correct IP cannot override that block. If only discovery is blocked, a reachable direct address may work. A timeout alone does not identify isolation conclusively.

Use a network you control for initial LAN operation. Hotspot/USB networking require device tests. VPN/relay support is future work and needs a permitted route. Do not expose the command port publicly or disable firewall protections as a workaround. See [mobile connections](mobile-connections.md).

Monitoring is deferred. Its standalone app/website compatibility plan is in [monitoring integration](monitoring-integration.md).

## HTTPS identity and certificates

The prototype creates a self-signed, one-year certificate for the selected address in Current User / Personal. Its private key stays in the Windows user key store. No root certificate is trusted automatically, and the app does not run an HTTP fallback.

A phone browser will initially show a certificate warning. Before making a site-specific exception, verify that the address is the one displayed by the PC and compare the certificate's SHA-256 fingerprint with settings where the browser exposes it. Use Export public certificate if a trusted transfer or certificate inspection is needed; the exported `.cer` contains no private key. If the phone cannot verify the certificate identity, complete that setup separately rather than treating encryption alone as proof of identity. Do not broadly disable certificate validation.

Browser certificate inspection/exception controls differ, and this is a prototype setup friction. Future Flutter clients should use an explicit pairing/identity-verification flow with certificate pinning, rather than accepting all self-signed certificates. An IP change or certificate renewal may require a new browser exception; confirm the new identity on the PC.

## Windows Firewall

The app does not automatically create firewall rules, request elevation, or change the network profile. Localhost testing needs no inbound LAN rule. If the phone cannot connect, check the selected address and network isolation before adding a rule.

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
- Silent TapMyPC notifications show remote activity without activating the window. The final ten seconds of a pending power action show a cancel button. Advanced settings can disable these custom notifications. This does not disable Windows' own media/volume overlays. Exclusive-fullscreen visibility still needs manual verification.
- There is one pending power action. Cancel it before scheduling a different one. The timer runs on the PC after browser disconnection and after stopping the API listener.
- Exiting the process cancels the timer. Timers are not persisted, do not wake a sleeping PC, and cannot be canceled once execution begins.
- Shutdown/restart never pass `/f`. Windows or unsaved work may block the transition. Sleep/hibernate use the existing user shutdown privilege, enabled temporarily during execution; no elevation prompt is requested.

## Audio outputs, shortcuts, and monitors

The phone's Sound card lists connected audio outputs. Choose one and select Use output. This changes Windows default playback and communications roles; apps pinned to a specific device may keep using it. Unplugged/disconnected outputs are rejected. The isolated Windows adapter uses the IPolicyConfig compatibility interface, which is not a documented public Windows API; Windows updates may affect switching, and failures are surfaced.

In the PC app, expand App & website shortcuts. Enter a name, then choose an .exe/.lnk application or enter an http(s) website and Add website. Only locally approved entries appear on the phone. Remove an entry on the PC to reject future launches by its ID. Application arguments can be configured in a locally approved .lnk file; no remote command-line input is accepted. Shortcuts are saved in %LOCALAPPDATA%\TapMyPC\shortcuts.json. Missing applications produce an error when launched.

The phone's Your monitors card shows each display's brightness slider and power buttons. Unsupported controls are disabled with an explanation. Built-in brightness uses Windows WMI when supported; external monitors use DDC/CI, which may need enabling in the monitor's physical menu. Adapters, docks, drivers, HDR modes, and monitor firmware can affect support. All-monitors-off remains available separately.

Individual off requests use DDC power-saving mode. Some monitors stop accepting DDC commands or disappear from Windows while off and require their physical button to wake; the UI reports an unreachable display rather than claiming it can turn it on. Commands report a request, and device refresh reads back the available state.

Use Refresh devices on the phone after plugging/unplugging devices or editing shortcuts. Lists also refresh on connection and after relevant commands. Hardware queries are not part of the two-second status polling loop.

## Bluetooth on/off

The phone remote has a Bluetooth card showing On, Off, Mixed, Disabled, or Unavailable, plus explicit Turn on / Turn off buttons. It controls the PC's Bluetooth radios over the existing Wi-Fi connection. Turning it off disconnects Bluetooth peripherals; confirm before sending that request. It never changes Wi-Fi or disables devices through Device Manager.

The first change may require Windows consent on the PC. Missing adapters, disabled radios, or rejected access are reported without blocking other remote controls. Status reads do not request permission. A command accepted by Windows may still be transitioning; the remote refreshes the effective state.

This controls radio power only. Pairing Bluetooth peripherals and using Bluetooth as the phone-to-PC transport are separate features and remain unimplemented.

## Startup and local data

Startup is off by default. The checkbox writes a per-user Run entry that launches the current executable with `--tray`. This mode starts the saved host and keeps the window hidden. Use a stable published executable path before enabling startup. Remove the checkbox before moving/deleting that executable.

Host preferences and paired-client hashes live in `%LOCALAPPDATA%\TapMyPC\host.json` and `devices.json`. Certificate keys are stored separately in the Windows user certificate/key stores. Do not edit these files while the app is running. Corrupt or inaccessible configuration is reported rather than silently discarded.

The dashboard has a custom frameless title bar with minimize, maximize/restore, and hide-to-tray buttons. Technical connection overrides, certificate tools, sign-in startup, notifications, and paired-device management are under Advanced settings.

### Upgrade from PC Remote

The application is now named TapMyPC and launches as `TapMyPC.exe`. It reads legacy `%LOCALAPPDATA%\PCRemote` preferences and paired-client records if the corresponding new TapMyPC files do not exist. New writes use `%LOCALAPPDATA%\TapMyPC`. Existing browser credentials migrate to the new local-storage name on page reload, and valid legacy certificates are reused to preserve server identity.

Exit the old PC Remote instance before opening TapMyPC; both versions share an instance lock to prevent conflicting listeners and timers. If sign-in startup was already enabled, launching TapMyPC migrates that existing opt-in to its current executable path. No startup entry is created for users who had not enabled it. The new executable name/path may require updating a program-scoped firewall rule; no rule is changed automatically.

## Publish

```powershell
dotnet publish src/TapMyPC.Desktop -c Release -r win-x64 --self-contained false -o artifacts/publish/TapMyPC
```

Run `TapMyPC.exe` from that folder. Keep its companion files together. This is a folder deployment, not an installer, and requires both .NET 10 Windows Desktop and ASP.NET Core runtimes on the target PC. The development machine already has them.

## Apply a staged update

When the existing published app is running, build the next version separately:

```powershell
dotnet publish src/TapMyPC.Desktop -c Release -r win-x64 --self-contained false -o artifacts/publish/TapMyPC-next
```

Exit the old app using its tray menu when convenient; pending timers will be canceled. Then, from the repository directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Apply-Update.ps1
```

Open the usual `artifacts/publish/TapMyPC/TapMyPC.exe` afterward, then start the host and reload the phone page. The script refuses to update a running copy. It copies staged files into the existing location, leaves user preferences/paired devices untouched, and preserves the executable path used by startup and program-scoped firewall rules. It does not kill the old host, change firewall settings, or run PC controls. Optional `-Launch` starts the updated executable after copying; it is not used automatically by the agent.

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

The user has confirmed phone Wi-Fi connectivity. Certificate trust, native mutating controls, interactive tray behavior, and sign-in startup still require further verification. IPv6, QR discovery, installation, presets (deferred), remote input (deferred), display arrangement, Flutter, Bluetooth transport/peripheral pairing, and remote wake are not implemented. The current build is a prototype, not a verified production release.
