# Bluetooth secondary connection

TapMyPC Android supports encrypted Classic Bluetooth RFCOMM with the Windows host. See [current versions](setup.md#versions-and-qr-visibility).

## Setup and normal use

1. Update both apps and start connections on the PC. Keep Bluetooth on on both devices.
2. Pair/reconnect over Wi-Fi once. Authenticated status supplies the PC's Bluetooth address and service identifier, saved with that PC's protected profile. Existing credentials and certificate identity are reused.
3. On Android open **Settings > Connection** for the selected PC and choose **Bluetooth only**. Allow Nearby devices when requested. Confirm the matching system pairing code on both devices if prompted. TapMyPC keeps the previous connection mode until pairing finishes.
4. **Automatic** tries the local network, Tailscale, then Bluetooth. **Bluetooth only** stays on Bluetooth. See [all connection choices](tailscale.md#connection-choices).
5. The phone labels an active Bluetooth connection. The PC shows each active phone's name with a blue **Bluetooth** badge when it has authenticated over Bluetooth. The separate Bluetooth readiness line shows listener availability.

Initial enrollment requires reachable trusted Wi-Fi. An already enrolled phone with saved Bluetooth metadata can control the PC without a LAN. Use [Wake-on-LAN](setup.md#android-wake-on-lan) over the local network when the PC is asleep and supports wake.

Start/Stop connections controls the LAN, Tailscale, and Bluetooth listeners and remains remembered. Public or unidentified LANs pause the local listener while Bluetooth remains available to already paired phones. Turning off either radio or moving out of range disconnects Bluetooth. While connected over Bluetooth, Android disables PC radio changes and the Bluetooth listener rejects them. Switch to local network or Tailscale to change radio power. The card offers the applicable action when it knows the radio is on or off. TapMyPC sends each command once.

## Phone names and active transport

New Android enrollment uses the OS device name, falling back to the model without requiring Bluetooth permission. Existing paired phones report that name during authenticated requests and update the saved label without re-pairing or changing credentials. The phone name is display metadata, not proof of identity.

In desktop Configure > Authorized phones, select a phone, edit Phone name, and select Save phone name. This local override persists and takes priority over future OS-reported names. Each PC owns its own custom labels.

Transport labels reflect the listener that last authenticated that client. Requests cannot choose or spoof their transport label. Presence still means authenticated activity within ten seconds, including availability probes and commands that later fail; it is not proof of the phone's selected PC or a permanent socket.

## Transport and identity

Windows advertises custom Classic Bluetooth RFCOMM service 8cf69287-4d5e-47f1-97c8-0a4ec3b5d290 using an authenticated, encrypted Bluetooth socket. The server forwards opaque bytes only to its own fixed loopback HTTPS listener. Android's native BluetoothSocket adapter exposes a temporary phone-loopback socket to the existing Dart TLS client.

The phone verifies the enrolled leaf/identity-key pin and certificate dates before sending any HTTP request or credential. A Bluetooth name, MAC address, OS bond, or service UUID never authorizes control by itself. The same bearer authentication, revocation, validation, request limits, feedback, power confirmations, and PC-owned timers apply across all listeners. No arbitrary forwarding destination, plaintext command protocol, unauthenticated localhost exemption, or separate command implementation is introduced.

The PC’s Bluetooth address is learned only from authenticated status. Saved fields are optional bluetoothAddress and connectionMode (auto by default) alongside the existing keyPin. The HTTPS LAN address and selected-profile identity remain unchanged when using the temporary local socket. Re-pairing/key reset retains the existing explicit identity-verification rules.

Connection recovery sends only read-only status probes. A failed command is reported without retrying it on another transport, preventing duplicate media, shortcut launches, or power scheduling. An authentication rejection requires re-pairing rather than transport fallback. Changing PCs isolates responses and never selects another PC because one connection failed.

## Platform implementation and limits

WindowsRfcommServer owns adapter checks, advertisement, encrypted accept, four concurrent streams, cancellation, and cleanup. Its target must be loopback. WinRT stream adapters disable buffering so small TLS/HTTP messages are delivered immediately. BluetoothConnectionHost composes that transport with the existing ApiHost and shared Core services. When Windows resumes with connections enabled, TapMyPC closes the old Bluetooth listener and advertises the service again. The existing ten-second host health check retries if the radio is still coming back. It also renews certificates without changing the identity key.

Android requests BLUETOOTH_CONNECT on Android 12+; legacy Bluetooth permissions are restricted to Android 11 and earlier. It needs no Bluetooth scanning or location permission because the authenticated PC supplies its address. Optional HTTP requests share one Bluetooth TLS/RFCOMM stream rather than opening simultaneous same-service connections. Native sockets have bounded connection timeouts and close when the Dart client, profile, or activity closes. Nearby devices permission denial and disabled radios remain visible; Wi-Fi stays available.

The connection uses Classic Bluetooth RFCOMM. Adapter support, driver policies, radio interference, and OS pairing behavior can affect availability.

## Platform references

- [Microsoft RFCOMM APIs](https://learn.microsoft.com/en-us/windows/uwp/devices-sensors/send-or-receive-files-with-rfcomm)
- [Android secure Bluetooth sockets](https://developer.android.com/develop/connectivity/bluetooth/connect-bluetooth-devices)
- [WinRT buffering and latency](https://learn.microsoft.com/en-us/windows/apps/develop/performance/optimize-file-access)
