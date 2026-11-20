# TapMyPC Android client

Android **0.18.4 (build 48)** gives QR pairing a dedicated review step and adds green and gray availability dots to the PC picker. **About TapMyPC** in Settings offers copyable app and PC host versions, setup help, third-party licenses, and the GitHub repository link. The app offers launcher shortcuts and a configurable TapMyPC Controls widget. The app remembers the Remote Desktop audio toggle for each PC. PC audio requires Windows **0.16.0 (build 27)** or newer and permission for the paired phone.

Android saves paired PC profiles, reconnects automatically, and controls audio, media, displays, shortcuts, and power. **Power > Wake PC** is available on the PC’s local network when it supports wake. Android learns settings from desktop **0.9.0 (build 13)** and supports per-PC manual overrides. See [Wake-on-LAN setup](../docs/setup.md#android-wake-on-lan).

Open **Settings > Connection** to choose Automatic, Local network only, Tailscale only, or Bluetooth only. TapMyPC learns separate local and Tailscale addresses from authenticated status. Both address editors accept a bare IP and reuse the saved port. **Advanced** reveals the editable port and **Back** returns to Connection. See [Tailscale setup](../docs/tailscale.md).

iOS deployment remains deferred. Manual enrollment retains the browser protocol. QR uses the single-use `/api/v1/pair/qr` endpoint.

## QR pairing

Open the PC app: connections start on trusted networks and the first QR appears automatically. Use Add another phone for subsequent enrollment. In Android select Add PC -> Scan PC QR, allow camera access, scan the displayed invitation, review the PC, then Pair with this PC. The bundled native decoder processes frames on the phone. QR images are not uploaded to an external service.

Invitations contain a random 256-bit secret, HTTPS address, certificate fingerprint, PC name, expiration, type, and version. The TLS pin is verified before the secret leaves the phone. A successful QR or manual pairing consumes the shared five-minute invitation. Regeneration and host stop invalidate it. Saved credentials are independent of the QR.

Manual entry stays available if camera access is unavailable. Profiles are distinguished by certificate pins, which the PC now reuses across IP changes. Native Android NSD supplies untrusted address hints; pinned HTTPS verification is mandatory before using any hint.

## Manual connection

Start the host in the PC app. In Advanced settings copy its SHA-256 certificate fingerprint. On Android select Add PC, enter a friendly name, the displayed HTTPS address, the fingerprint, and a freshly generated one-time code. Compare the fingerprint using the local PC app, not an unverified network source.

Connections use an empty TLS trust store and a dedicated TLS socket which verifies the enrolled leaf fingerprint or a previously verified identity-key pin, plus validity, before HTTP receives the socket. Redirects are not followed. Credentials/profile data use flutter_secure_storage; Android backup is disabled. Address changes recover automatically when discovery reaches the PC. Same-key renewal preserves updated profiles. Missing/replaced keys require desktop reset and Android Settings > Re-pair selected PC. Leaf-only profiles must connect once to learn keyPin before their first renewal, or pair again afterward.

Pairings persist across app restarts. Selecting another PC isolates old responses and never redirects actions. Commands are not automatically retried. Forget removes the saved local profile; revoke on the PC to invalidate its credential.

**Stats** shows the selected PC's hardware readings when the Windows host and PC Stats Tray are running. Use **Show all** to expand the default view. [Hardware monitoring](../docs/monitoring-integration.md)

## Development

Requires Flutter and an Android SDK/JDK. Use flutter analyze, flutter test, and flutter build apk --debug. Connect an authorized USB-debugging device and use flutter run -d DEVICE_ID.

The app uses package ID `dev.tapmypc.tapmypc_mobile`. Both debug and release builds use the Android debug signing configuration.

## Automatic connection

Open both apps on a reachable trusted LAN after pairing once. Android remembers the selected PC, discovers saved PCs while foregrounded, verifies pinned TLS identity, and refreshes authenticated status. Other saved PCs show availability; commands never fall back to another PC and are not replayed during recovery. The Help button explains this flow in the app.

Stop connections on the PC persists across restarts. Start connections resumes. Public/isolated networks may prevent control; discovery cannot bypass blocked traffic. Bluetooth secondary transport is implemented. See [Bluetooth setup](../docs/bluetooth.md).

## Phone names and radio controls

The Android OS device name (model fallback) identifies the phone during pairing and authenticated reconnection. Existing credentials remain valid. PC-side custom names take priority. The desktop shows the phone and its actual most-recent authenticated transport.

Devices shows PC Bluetooth: On/Off and one applicable action over Wi-Fi or Tailscale. Actual Bluetooth connections disable radio changes, including Automatic fallback. Unknown/unavailable/mixed states cannot offer a guessed action. No new Android permission is needed for the device-name lookup.

## Bluetooth secondary connection

Connect to the PC over Wi-Fi once to save authenticated Bluetooth metadata. Open **Settings > Connection** and choose **Bluetooth only**. Allow Nearby devices and confirm the matching pairing code on both devices if prompted. When pairing succeeds, the phone switches to Bluetooth and verifies the existing PC identity. After the first setup, **Automatic** can use Bluetooth when the network is unavailable. Both radios must be on. The phone shows which connection is active, and commands never retry across transports.

Native Android carries opaque TLS bytes over secure RFCOMM; the existing Dart client verifies the PC identity before sending credentials. Old profile JSON remains compatible through optional bluetoothAddress and connectionMode fields. See [Bluetooth setup and architecture](../docs/bluetooth.md).

## Home-screen controls

- Open TapMyPC once and select a paired PC. On launchers that support app shortcuts, long-press the TapMyPC icon to find **Remote Desktop** and, when Wake-on-LAN is configured for the selected PC, **Wake**. Android app shortcuts require Android 7.1 or newer.
- Choose **TapMyPC Controls** from the launcher's widget picker and select a paired PC. Each widget keeps its own PC. Tap the widget header to choose a different one.
- **Wake PC** sends one wake packet using that PC's saved settings and the current local Wi-Fi route. A sent packet does not confirm that the PC woke.
- **Desktop** opens the viewer when the selected PC grants permission and is reachable over Wi-Fi or Tailscale. **Refresh** performs an authenticated check against the saved Wi-Fi or Tailscale endpoints and shows the result and time. Use the app to check Bluetooth-only connections. Widgets do not poll in the background.

## Android presentation

- **Remote:** volume and mute, an audio-output sheet, media transport, and locally approved shortcuts.
- **Devices:** all-screen off, individual monitor capabilities/brightness/power, and Bluetooth radio control with disconnect confirmation.
- **Power:** named-PC confirmation for every power action and editable timer durations. Pending countdowns stay above bottom navigation. While offline, cancellation is disabled and the card hides when the countdown is due.
- The selected PC and connection feedback remain visible. PC switching, activity, and settings use focused sheets. Successful/failed command feedback is retained while status polling continues, and no action is automatically retried. Optional device-list failures leave the verified connection and other controls usable; their specific warnings clear after a successful refresh. Failed lists retry on the existing ten-second polling cadence, and authentication rejection still requires pairing.
- Settings offers the desktop's five accent palettes, saved independently of PC credentials, and transitions that automatically respect Android reduced motion; there is no separate animation setting. Static Inter fonts and their OFL are bundled; the launcher/splash use the TapMyPC mark and dark surfaces.
- First connection uses one setup card with two pairing steps and a single Add your PC action. The initial app bar omits the version; Settings > About TapMyPC always shows it, and the dashboard header shows it once a PC is saved. Version/build is read from the installed Android package. PC serverVersion is shown separately.

`flutter test` includes presentation/action-routing, offline/busy, PC selection, timer cancellation, appearance persistence, and small-screen/large-text checks. Visual previews are generated under ignored `artifacts/mobile-ui/`.
