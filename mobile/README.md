# TapMyPC Android client

Installed development build: **0.6.2 (build 12)**, streamlining first connection into one setup card while retaining encrypted Bluetooth secondary connectivity, protected Bluetooth metadata, and per-PC Automatic/Wi-Fi-only/Bluetooth-only selection. Certificate renewal/recovery is included. Installation results are recorded in [verification](../docs/verification.md). Native Flutter client for the existing authenticated HTTPS API. Current scope: QR/manual pinned certificate enrollment, protected saved PC profiles, automatic saved-PC discovery and address recovery, PC selection, audio/output/media controls, power confirmations and 30-minute timers, Bluetooth radio control, monitor controls, and approved shortcuts.

Configurable timer durations and iOS deployment are not implemented yet. Hardware monitoring is next. Laptop Wi-Fi wake investigation is closed for the current configuration; remote wake sending remains unimplemented. See [wake investigation](../docs/wake-investigation.md). Manual enrollment retains the browser protocol; QR uses the new single-use /api/v1/pair/qr endpoint.

## QR pairing

Open the PC app: connections start on trusted networks and the first QR appears automatically. Use Add another phone for subsequent enrollment. In Android select Add PC -> Scan PC QR, allow camera access, scan the displayed invitation, review the PC, then Pair with this PC. The bundled native decoder processes frames on the phone. QR images are not uploaded to an external service.

Invitations contain a random 256-bit secret, HTTPS address, certificate fingerprint, PC name, expiration, type, and version. The TLS pin is verified before the secret leaves the phone. A successful QR or manual pairing consumes the shared five-minute invitation. Regeneration and host stop invalidate it. Saved credentials are independent of the QR.

Manual entry stays available if camera access is unavailable. Profiles are distinguished by certificate pins, which the PC now reuses across IP changes. Native Android NSD supplies untrusted address hints; pinned HTTPS verification is mandatory before using any hint.

## Manual connection

Start the host in the PC app. In Advanced settings copy its SHA-256 certificate fingerprint. On Android select Add PC, enter a friendly name, the displayed HTTPS address, the fingerprint, and a freshly generated one-time code. Compare the fingerprint using the local PC app, not an unverified network source.

Connections use an empty TLS trust store and a dedicated TLS socket which verifies the enrolled leaf fingerprint or a previously verified identity-key pin, plus validity, before HTTP receives the socket. Redirects are not followed. Credentials/profile data use flutter_secure_storage; Android backup is disabled. Address changes recover automatically when discovery reaches the PC. Same-key renewal preserves updated profiles. Missing/replaced keys require desktop reset and Android Settings > Re-pair selected PC. Leaf-only profiles must connect once to learn keyPin before their first renewal, or pair again afterward.

Pairings persist across app restarts. Selecting another PC isolates old responses and never redirects actions. Commands are not automatically retried. Forget removes the saved local profile; revoke on the PC to invalidate its credential.

## Development

Requires Flutter and an Android SDK/JDK. Use flutter analyze, flutter test, and flutter build apk --debug. Connect an authorized USB-debugging device and use flutter run -d DEVICE_ID.

On this Windows machine, Controlled Folder Access blocks some generated files under Documents. The initial build used a source copy at C:\temp\TapMyPC-mobile-build, excluding build, .dart_tool, .gradle, and local.properties. Keep edits in this repository and sync source to the build copy before building. Do not disable folder protection.

The test APK uses the normal package ID dev.tapmypc.tapmypc_mobile. Release signing/distribution has not been configured; current APKs are development builds.

## Device integration test

Run the isolated desktop simulator, note its ephemeral fingerprint and one-use code, and forward only its loopback port with adb reverse tcp:45832 tcp:45832. Run:

flutter test integration_test/remote_test.dart -d DEVICE_ID --dart-define=TEST_PIN=FINGERPRINT --dart-define=TEST_CODE=CODE

The test verifies wrong-pin rejection before enrollment, encrypted profile persistence, authenticated status, and simulated mute. It restores prior profiles afterward. It never targets the real Windows host or native PC controls. Test pairing codes are for the simulator only; no test credentials are included in the normal app.

Verified on the connected Android 16 device: wrong-pin rejection, simulator enrollment, secure saved-profile roundtrip, native status screen, and simulated mute passed. Real host controls need user testing. QR enrollment and automatic discovery are implemented.

## QR device test

integration_test/qr_pairing_test.dart decodes a PNG generated by the actual desktop pairing view model using Android's bundled native decoder. Supply TEST_QR_IMAGE (base64 PNG) and TEST_PC_NAME via a temporary --dart-define-from-file fixture. The isolated loopback host issues one ephemeral invitation, and adb reverse forwards only its test port.

The test checks decoding, wrong-pin rejection before redemption, successful enrollment, replay rejection, secure profile storage, and connection in the native UI. It restores prior profiles. Live camera aiming and runtime permission interaction remain manual device checks. Never include real pairing invitations in source control or normal APK test configuration.

## Automatic use (v0.3.0, build 3)

Open both apps on a reachable trusted LAN after pairing once. Android remembers the selected PC, discovers saved PCs while foregrounded, verifies pinned TLS identity, and refreshes authenticated status. Other saved PCs show availability; commands never fall back to another PC and are not replayed during recovery. The Help button explains this flow in the app.

Stop connections on the PC persists across restarts. Start connections resumes. Public/isolated networks may prevent control; discovery cannot bypass blocked traffic. Bluetooth secondary transport is implemented. See [Bluetooth setup](../docs/bluetooth.md).

The reconnection_test.dart device test combines actual desktop mDNS advertisement, Android NSD, one-time QR enrollment, wrong-pin/replay rejection, stale-address recovery, protected storage, remembered selection, and the in-app help dialog. Run with the same temporary QR fixture plus TEST_LAN_ADDRESS; the simulator must be reachable from the phone. Restore saved profiles and selection after device tests.

## Phone names and radio controls

The Android OS device name (model fallback) identifies the phone during pairing and authenticated reconnection. Existing credentials remain valid. PC-side custom names take priority. The desktop shows the phone and its actual most-recent authenticated transport.

Devices shows PC Bluetooth: On/Off and one applicable action on Wi-Fi. Actual Bluetooth connections disable radio changes, including Automatic fallback. Unknown/unavailable/mixed states cannot offer a guessed action. No new Android permission is needed for the device-name lookup.

## Bluetooth secondary connection

Connect to the PC over Wi-Fi once to save authenticated Bluetooth metadata. Open Settings > Connection, allow Nearby devices, and choose Automatic, Wi-Fi only, or Bluetooth only. Phone Bluetooth settings opens Android settings for radio power/system pairing. Both radios must be on. Already enrolled profiles can then control without LAN access. The phone labels active Bluetooth control; commands never retry across transports. Initial QR/manual enrollment stays on Wi-Fi.

Native Android carries opaque TLS bytes over secure RFCOMM; the existing Dart client verifies the PC identity before sending credentials. Old profile JSON remains compatible through optional bluetoothAddress and connectionMode fields. See [Bluetooth architecture and hardware tests](../docs/bluetooth.md).

## Android presentation

- **Remote:** volume and mute, an audio-output sheet, media transport, and locally approved shortcuts.
- **Devices:** all-screen off, individual monitor capabilities/brightness/power, and Bluetooth radio control with disconnect confirmation.
- **Power:** named-PC confirmation for every power action and the existing 30-minute timers. Pending actions remain above bottom navigation, including a last-known countdown offline; cancellation is disabled until reconnected.
- The selected PC and connection feedback remain visible. PC switching, activity, and settings use focused sheets. Successful/failed command feedback is retained while status polling continues, and no action is automatically retried. Optional device-list failures leave the verified connection and other controls usable; their specific warnings clear after a successful refresh. Failed lists retry on the existing ten-second polling cadence, and authentication rejection still requires pairing.
- Settings offers the desktop's five accent palettes, saved independently of PC credentials, and transitions that automatically respect Android reduced motion; there is no separate animation setting. Static Inter fonts and their OFL are bundled; the launcher/splash use the TapMyPC mark and dark surfaces.
- First connection uses one setup card with two pairing steps and a single Add your PC action. The initial app bar omits the version; Settings > About always shows it, and the dashboard header shows it once a PC is saved. Version/build is read from the installed Android package. PC serverVersion is shown separately. See [versioning](../docs/versioning.md).

`flutter test` includes presentation/action-routing, offline/busy, PC selection, timer cancellation, appearance persistence, and small-screen/large-text checks. Visual previews are generated under ignored `artifacts/mobile-ui/`.

`integration_test/ui_overhaul_test.dart` uses a loopback simulator fixture (`TEST_ADDRESS`, `TEST_PIN`, `TEST_CODE`) to verify pinned enrollment, installed version, mute, explicit Bluetooth disable confirmation, a 30-minute timer and cancellation, theme persistence, help, and QR/manual enrollment layout. It saves simulated UI screenshots in the test app temporary directory. During this overhaul it is run in an isolated build copy with applicationId `dev.tapmypc.tapmypc_mobile.uitest`; the normal app's saved PCs are not changed. Do not target the real Windows control host in unattended device tests.
