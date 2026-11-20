# Local network, Tailscale and Bluetooth

TapMyPC saves separate local and Tailscale addresses for each paired PC. All routes share the existing pinned HTTPS identity, token, commands and PC-owned timers.

## Set up Tailscale

1. Connect Tailscale on the PC and Android phone to the same tailnet.
2. In the PC app open Configure > Remote access and enable **Allow access through Tailscale**. Normal local-network access stays available; no adapter switching is needed.
3. Open the paired PC on Android while any supported route is reachable. Authenticated status supplies the PC's active local and Tailscale addresses.
4. In Android Settings > Connection choose **Automatic**, or choose **Tailscale only** to use that route explicitly.
5. If the phone has not learned the address, select **Tailscale address**, enter just the 100.x IPv4 address shown on the PC, and select **Verify and save**. The existing TapMyPC port is reused. Advanced allows changing the port only when it differs on the PC. Pasting the complete HTTPS IP link also works.

Both address editors return to Connection with **Back**. Expanding **Advanced** brings the TapMyPC port into view. Changing an address verifies exactly that endpoint before saving. It does not change the connection preference unless setup was opened by choosing Tailscale only. Failed verification leaves the old profile intact and shows feedback. Existing pairing is preserved.

To test access from outside your home network, keep the PC awake, turn off Wi-Fi on the phone, and use cellular data. The app reports **Connected · Tailscale** when it reaches the PC through that route. Direct access between your Tailscale devices works with **Exit Node** set to **None**.

## Connection choices

| Phone choice | Behavior |
| --- | --- |
| Automatic | Try saved/discovered local addresses, then the saved Tailscale address, then Bluetooth when its metadata is available. While using Tailscale/Bluetooth, check for a preferred network route on the existing ten-second cadence. |
| Local network only | Use local addresses; never fall back to Tailscale or Bluetooth. |
| Tailscale only | Use the saved Tailscale address; never fall back to local or Bluetooth. |
| Bluetooth only | Use Bluetooth without probing network addresses. |

Bluetooth remains selectable near the PC even if Tailscale is configured. Bluetooth permission is needed for Bluetooth; it does not block saving Automatic or using local/Tailscale access. Only actual Bluetooth control disables PC Bluetooth-radio changes.

Only read-only status establishes or recovers connections. No command is automatically resent across routes. Rejected credentials stop recovery and require re-pairing. Every candidate must pass the saved TLS identity before it receives a credential.

## PC behavior and limits

- The PC independently hosts one selected trusted local IPv4 address and, when enabled, an active Tailscale IPv4 address on the same TapMyPC port (default 45831). Bluetooth remains independent.
- Local adapter Automatic excludes Tailscale. LAN listeners still require Windows Private/Domain classification. The Tailscale opt-in recognizes interface metadata plus its default 100.64.0.0/10 range without changing Windows classification.
- Losing either network stops only that listener. Returning adapters resume while connections are enabled. Turning off Tailscale leaves LAN and Bluetooth available.
- Global Stop connections pauses every listener and persists across restart. Restarting listeners or changing routes does not cancel PC-owned timers.
- Local discovery advertises only the trusted LAN listener. Authenticated status contains optional networkConnection.localAddress and networkConnection.tailscaleAddress location hints. Disconnected/disabled listeners report null; saved clients retain last-known hints and verify before use.
- Numeric HTTPS IPv4 addresses remain required by strict Host validation. MagicDNS, IPv6 and custom Tailscale IP pools are outside this implementation. Tailscale Serve/TLS termination is not configured.
- Tailscale carries TapMyPC commands while the PC is awake, online, and running the host. The Android [Wake PC action](setup.md#android-wake-on-lan) sends its packet over the local Wi-Fi network. Waking from outside that network requires a separate always-on device that can relay the wake packet on the home network.

## Compatibility

Old PC settings that explicitly selected a Tailscale IP migrate to Automatic local selection with the Tailscale opt-in enabled. Other PC settings leave Tailscale disabled by default. Stop/start preference, identity, credentials and other preferences are retained.

Old Android profiles retain pins and credentials. A previous combined wifi preference becomes Local network only for a LAN IP, or Tailscale only for a Tailscale IP. Automatic and Bluetooth-only preferences remain. Missing address slots are learned through authenticated status; changing one slot never overwrites the other.

## Firewall and tailnet policy

No account login, router forwarding, firewall rule or public listener is created automatically. Tailnet policy and Windows Firewall must allow the phone to reach the PC and TapMyPC port. A LAN rule limited to LocalSubnet or Private profiles may not cover Tailscale. A dedicated rule, when needed, should be scoped to the app, Tailscale interface, local Tailscale IP, port and intended phone/peers.

Tailscale documents its default range in [What are these 100.x addresses?](https://tailscale.com/docs/concepts/tailscale-ip-addresses) and reachability in [Connect to devices](https://tailscale.com/docs/how-to/connect-to-devices).
