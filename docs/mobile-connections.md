# Mobile connections and trust

Current installed development versions: desktop/server **0.3.4 (build 7)** and Android **0.4.3 (build 7)**. QR enrollment, saved PC discovery/reconnection, stable certificate identity across IP changes, and remembered desktop connection state were introduced in the earlier 0.3.0 work. Monitoring is deferred. See [setup](setup.md) and [verification](verification.md) for current delivery evidence.

## Current Android enrollment

The PC automatically starts connections on a Windows Private/Domain network and opens an initial five-minute QR window when no phones are paired. Add another phone opens a fresh window; Show QR refreshes an expired initial invitation. The QR contains a versioned TapMyPC JSON payload with the PC name, HTTPS address, exact certificate SHA-256 fingerprint, expiration, and a random 256-bit single-use secret. It contains no permanent command credential.

The Android app scans locally, validates the payload, previews the PC, and verifies the pinned TLS certificate before sending the secret to /api/v1/pair/qr. Successful redemption returns a normal persistent per-phone credential stored through platform secure storage. No typing is needed in the QR path. Manual address/fingerprint/code entry remains available.

QR and browser/manual code enrollment share one window. Successful use of either consumes both. Regeneration, expiration, five invalid attempts, or stopping/exiting the host closes that window; the desktop hides the QR after observing closure. No HTTP endpoint generates or exposes QR invitations. Payloads/secrets are not logged.

Saved profiles distinguish pinned certificates rather than just IP addresses. Reconnection tries saved addresses and matching mDNS hints. The desktop remembers its existing certificate in identity.json and reuses it across IP changes. Certificate renewal/replacement still requires explicit recovery; a different certificate is never silently trusted. See [mobile setup](../mobile/README.md).

## Current prototype

The browser uses a manual HTTPS address and a single-use six-digit pairing code. Pairing creates a persistent per-client bearer credential; the PC stores its hash and supports revocation. Reconnects do not inherently require another code. Browser credentials are origin-bound, so an address change affects access to saved browser storage.

Normal desktop launch resumes connections unless Stop connections was previously selected. A network change restarts the listener on the selected trusted adapter; Public/unidentified networks remain paused. The app never changes Windows network categories or firewall rules.

## Automatic connection behavior

- Android discovers _tapmypc._tcp services with native NSD while foregrounded, and tries saved addresses. Advertisements contain a version, public certificate fingerprint and machine name, never a credential.
- Treat discovered names, IDs, and addresses as untrusted hints. Verify saved cryptographic identity before sending credentials or commands.
- Authenticate silently per PC; ordinary restarts, IP changes, and temporary disconnections do not require new enrollment.
- Existing valid certificates migrate into a persistent identity reference. Missing/expired certificates fail closed; renewal/key replacement and recovery remain future UI work. Never silently trust a replacement key.
- Start/Stop connections is remembered independently of Windows sign-in startup. Normal exit preserves that preference. No trusted network means waiting, with checks on network change and every ten seconds.
- Show selected-PC connection feedback plus per-PC Connected, Available, Offline/searching, or Pairing required. Foreground reads retry automatically; saved selection persists. Revoked credentials require another QR.
- A successful pinned/authenticated status response establishes the selected-PC connection. Failed audio-output, monitor, or shortcut lists show a warning in the affected section and clear that list, without marking the PC offline. Failed device lists retry on the existing ten-second foreground cadence or on manual refresh. Failed status or rejected credentials still disable control; 401 requires pairing.
- Do not replay non-idempotent media, launch, or power-scheduling commands during reconnection.

Protect credentials with Keystore-backed encryption on Android and Keychain on iOS. Credential loss, PC-side revocation, or identity reset requires recovery/pairing. Do not assume app reinstall always removes platform keychain data.

## Multiple PCs

The Android client supports separately selected saved profiles for the user's home desktop and work laptop. The saved certificate fingerprint is the current stable identity; separate identity keys and automatic renewal remain planned. Pair each separately. Each profile owns its PC identity, friendly name, endpoint hints, trust pin, and credential. Each PC retains independent paired phones, capabilities, shortcuts, activity, and timers.

Keep selected PC visible, especially in power confirmations. Switching profiles must isolate responses and in-flight work. Never redirect commands or silently fall back to another PC. Future monitoring availability is per PC. The desktop connection badge reflects authenticated requests in the last ten seconds, including requests whose operation later fails; it does not establish that all hardware queries succeeded. See [connection feedback](action-feedback.md#main-window-connection-indicator).

## Security and validation

This is a development implementation, not a production security audit. Persistent pairing is compatible with secure operation when credentials are protected, PC identity is verified on every connection, and credentials remain revocable.

Test wrong-key rejection before credential transmission, QR expiry/reuse, rate limits, revocation, protected storage, per-PC isolation, IP changes, identity renewal/replacement, and reconnection without command replay. Discovery never grants authority. Preserve input validation and power confirmations.

## Reachability and alternatives

Saved pairing cannot make blocked traffic pass. A connection timeout alone does not prove isolation.

| Situation | Expected behavior |
| --- | --- |
| Reachable trusted LAN, PC wired or wireless | Existing IP API can work with correct host/firewall setup |
| Discovery blocked but direct traffic allowed | Last-known/manual address may work; verify identity |
| AP/client isolation blocks peer traffic | QR, saved pairing, and a known IP cannot restore direct control |
| Different networks or mobile data | Current LAN implementation has no route by itself |
| Personal hotspot/private router | Candidate alternate LAN; test phone-to-client traffic, discovery, and firewall profile |
| USB networking/tethering | Future candidate; support and addressing require device/platform tests |
| VPN/overlay or encrypted outbound relay | Future remote-access option; needs a permitted routed/relayed path and may be blocked by network policy |

Ethernet does not guarantee an isolated Wi-Fi phone can reach a wired PC. A VPN is not automatically a workaround: direct peer traffic may still be blocked; internet-based relaying/routing may be required.

Do not bypass managed-network policy, disable firewall protections, or expose/forward the command port publicly. Public-network hosting is not enabled automatically. Bluetooth transport, USB, Wi-Fi Direct, and internet relay are not implemented. Existing Bluetooth radio on/off is a different feature.

## References

- [Android discovery](https://developer.android.com/develop/connectivity/wifi/use-nsd)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Apple Keychain](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain)
- [OWASP mobile network security](https://mas.owasp.org/MASVS/08-MASVS-NETWORK/)
- [Cisco Meraki isolation](https://documentation.meraki.com/Wireless/Operate_and_Maintain/How_Tos/Firewall_and_Traffic_Shaping/Wireless_Client_Isolation)
