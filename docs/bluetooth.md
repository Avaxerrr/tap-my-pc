# Bluetooth secondary connection

Implemented for the Windows host and Flutter Android client in desktop 0.5.0+9 and Android 0.6.0+10. The browser remains a Wi-Fi client; iOS is deferred.

## Setup and normal use

1. Update both apps and start connections on the PC. Keep Bluetooth on on both devices.
2. Pair/reconnect over Wi-Fi once. Authenticated status supplies the PC's Bluetooth address and service identifier, saved with that PC's protected profile. Existing credentials and certificate identity are reused.
3. On Android open Settings > Connection for the selected PC. Allow Nearby devices when requested. Choose Automatic, Wi-Fi only, or Bluetooth only. Complete Windows/Android system Bluetooth pairing if prompted; Phone Bluetooth settings opens the native settings screen.
4. Automatic starts with Wi-Fi and tries Bluetooth during connection recovery. It retains a healthy Bluetooth connection; reselect Automatic, reopen the app, or reselect the PC to start with Wi-Fi again. Wi-Fi only and Bluetooth only never silently use the other transport.
5. The phone labels an active Bluetooth connection. The PC shows Bluetooth readiness and counts authenticated traffic from either transport in its existing remote badge.

Initial enrollment requires reachable trusted Wi-Fi. An already enrolled phone with saved Bluetooth metadata can control the PC without a LAN. Saved pairing cannot wake a sleeping PC; remote wake is separate work.

Start/Stop connections controls both listeners and remains remembered. Public/unidentified LANs pause Wi-Fi without disabling Bluetooth for already paired phones. Turning off a PC/phone radio or moving out of range disconnects Bluetooth. Turning off the PC radio through Bluetooth can lose the response even when the radio command was applied; reconnect over Wi-Fi or turn the radio on locally. No command is automatically replayed.

## Transport and identity

Windows advertises custom Classic Bluetooth RFCOMM service 8cf69287-4d5e-47f1-97c8-0a4ec3b5d290 using an authenticated, encrypted Bluetooth socket. The server forwards opaque bytes only to its own fixed loopback HTTPS listener. Android's native BluetoothSocket adapter exposes a temporary phone-loopback socket to the existing Dart TLS client.

The phone verifies the enrolled leaf/identity-key pin and certificate dates before sending any HTTP request or credential. A Bluetooth name, MAC address, OS bond, or service UUID never authorizes control by itself. The same bearer authentication, revocation, validation, request limits, feedback, power confirmations, and PC-owned timers apply on both listeners. No arbitrary forwarding destination, plaintext command protocol, unauthenticated localhost exemption, or separate command implementation is introduced.

The phone's Bluetooth address is learned only from authenticated status. Saved fields are optional bluetoothAddress and connectionMode (auto by default) alongside the existing keyPin. The HTTPS LAN address and selected-profile identity remain unchanged when using the temporary local socket. Re-pairing/key reset retains the existing explicit identity-verification rules.

Connection recovery sends only read-only status probes. A failed command is reported without retrying it on another transport, preventing duplicate media, shortcut launches, or power scheduling. An authentication rejection requires re-pairing rather than transport fallback. Changing PCs isolates responses and never selects another PC because one connection failed.

## Platform implementation and limits

WindowsRfcommServer owns adapter checks, advertisement, encrypted accept, four concurrent streams, cancellation, and cleanup. Its target must be loopback. WinRT stream adapters disable buffering so small TLS/HTTP messages are delivered immediately. BluetoothConnectionHost composes that transport with the existing ApiHost and shared Core services. The existing ten-second host health check retries Bluetooth after radio/service failures and renews certificates without changing the identity key.

Android requests BLUETOOTH_CONNECT on Android 12+; legacy Bluetooth permissions are restricted to Android 11 and earlier. It needs no Bluetooth scanning or location permission because the authenticated PC supplies its address. Optional HTTP requests share one Bluetooth TLS/RFCOMM stream rather than opening simultaneous same-service connections. Native sockets have bounded connection timeouts and close when the Dart client, profile, or activity closes. Nearby devices permission denial and disabled radios remain visible; Wi-Fi stays available.

These builds use Classic RFCOMM, not BLE GATT. Classic support was detected and an actual encrypted exchange was verified on the development PC/Android phone. Other adapters, driver policies, range/interference, OS pairing UI, and long background/resume intervals still need broader device coverage.

## Verification tools

tools/TapMyPC.BluetoothTestHost starts the real Windows Bluetooth adapter with temporary settings/certificates and simulated command controllers. Its setup/control HTTP listeners bind loopback only and require a fresh test secret for control. Run it with a fixture JSON path under ignored artifacts. Stop through its authenticated /test/stop control endpoint so its own certificates/settings are removed.

mobile/integration_test/bluetooth_test.dart takes TEST_BLUETOOTH_FIXTURE as base64 fixture JSON through a temporary --dart-define-from-file file. Use a separate temporary Android applicationId, grant/request Nearby devices access, and forward only the fixture setup/control ports with adb reverse. Bluetooth data itself must cross the radios. The test closes the Wi-Fi endpoint before proving automatic fallback, checks command counts/timer cancellation/reconnect/revocation, and switches transports through the actual phone UI. It restores protected profile/selection state in the test app.

dotnet run --project tools/TapMyPC.CertificateUiCheck -c Release -- --bluetooth checks global start/pause, identity reset/resume, fresh QR, and timer preservation with the real Bluetooth listener and simulated PC operations. Run these hardware tools separately because they advertise the same service UUID. Normal APKs must be built from lib/main.dart without test defines.

## Platform references

- [Microsoft RFCOMM APIs](https://learn.microsoft.com/en-us/windows/uwp/devices-sensors/send-or-receive-files-with-rfcomm)
- [Android secure Bluetooth sockets](https://developer.android.com/develop/connectivity/bluetooth/connect-bluetooth-devices)
- [WinRT buffering and latency](https://learn.microsoft.com/en-us/windows/apps/develop/performance/optimize-file-access)
