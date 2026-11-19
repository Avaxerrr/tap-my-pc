# Mobile connections and trust

Current installed development versions: desktop/server **0.6.0 (build 10)** and Android **0.6.2 (build 12)**, adding encrypted Bluetooth secondary connectivity and saved transport preferences, including the earlier certificate work. Installation results are recorded in verification.md. QR enrollment, saved PC discovery/reconnection, stable certificate identity across IP changes, and remembered desktop connection state were introduced in the earlier 0.3.0 work. Hardware monitoring is next. Laptop Wi-Fi wake investigation is closed for the current configuration; remote wake remains unimplemented. See [wake investigation](wake-investigation.md). See [setup](setup.md) and [verification](verification.md) for current delivery evidence.

## Current Android enrollment

The PC automatically starts connections on a Windows Private/Domain network and opens an initial five-minute QR window when no phones are paired. Add another phone opens a fresh window; Show QR refreshes an expired initial invitation. The QR contains a versioned TapMyPC JSON payload with the PC name, HTTPS address, exact certificate SHA-256 fingerprint, expiration, and a random 256-bit single-use secret. It contains no permanent command credential.

The Android app scans locally, validates the payload, previews the PC, and verifies the pinned TLS certificate before sending the secret to /api/v1/pair/qr. Successful redemption returns a normal persistent per-phone credential stored through platform secure storage. No typing is needed in the QR path. Manual address/fingerprint/code entry remains available.

QR and browser/manual code enrollment share one window. Successful use of either consumes both. Regeneration, expiration, five invalid attempts, or stopping/exiting the host closes that window; the desktop hides the QR after observing closure. No HTTP endpoint generates or exposes QR invitations. Payloads/secrets are not logged.

Saved profiles distinguish pinned certificates rather than just IP addresses. Reconnection tries saved addresses and matching mDNS hints. The desktop remembers its existing certificate in identity.json and reuses it across IP changes. Renewed certificates are accepted only with a previously verified identity key and valid dates. A different key requires explicit local reset and fresh enrollment. See [mobile setup](../mobile/README.md).

## Certificate renewal and recovery

The desktop checks validity at listener startup and during its existing ten-second network checks. Within 30 days of expiry it stops/restarts only the listener and advertisement, issues a new one-year certificate with the same persisted RSA private key, and saves its new thumbprint. No certificate-store root trust, Windows clock, startup preference, or power timer changes are required. Old certificate entries are retained; they are not silently removed from the user's store.

Android initially checks the exact QR/manual SHA-256 leaf fingerprint. After a verified connection it derives SHA-256 of the DER SubjectPublicKeyInfo from the actual TLS certificate, persists it as optional keyPin in the existing protected profile, and still requires valid certificate dates. Valid renewed certificates with that key can use the existing bearer token. Renewal does not extend revoked phone access. Profiles without keyPin remain leaf-only until a successful verified connection upgrades them; a phone that never connected before renewal must re-pair. Update the phone before the desktop when a certificate is already near expiry. Older Android builds may require re-pairing after every certificate renewal.

Discovery adds pk=identity-key SHA-256 alongside the existing fp leaf fingerprint. Either saved identity can supply an address hint; TLS and bearer verification remain mandatory. Profile selection IDs remain stable across renewal. Profile writes are serialized and failed migration saves retry without replaying commands.

If the certificate/private key is missing or unusable, use desktop Configure > Advanced Network & Security > Reset connection identity. Confirm Reset and revoke all phones. The listener closes, a fresh key/certificate is created, all old credentials/invitations are persistently revoked, and connections resume only if previously enabled and the network is trusted. Pending timers continue. If paused/offline, the identity can still reset; resume connections on a trusted network to display a fresh QR.

On Android select the affected PC, then Settings > Re-pair selected PC. Explicitly scan and confirm that PC's new QR, or enter its new fingerprint and manual code. Only that profile is replaced; other PCs remain saved. No changed identity is accepted merely because its name/address matches. Browser users must verify the new fingerprint and accept the new self-signed certificate after renewal/reset.

## Current prototype

The browser uses a manual HTTPS address and a single-use six-digit pairing code. Pairing creates a persistent per-client bearer credential; the PC stores its hash and supports revocation. Reconnects do not inherently require another code. Browser credentials are origin-bound, so an address change affects access to saved browser storage.

Normal desktop launch resumes connections unless Stop connections was previously selected. A network change restarts the listener on the selected trusted adapter; Public/unidentified networks remain paused. The app never changes Windows network categories or firewall rules.

## Automatic connection behavior

- Android discovers _tapmypc._tcp services with native NSD while foregrounded, and tries saved addresses. Advertisements contain a version, public certificate fingerprint and machine name, never a credential.
- Treat discovered names, IDs, and addresses as untrusted hints. Verify saved cryptographic identity before sending credentials or commands.
- Authenticate silently per PC; ordinary restarts, IP changes, and temporary disconnections do not require new enrollment.
- Existing valid certificates migrate into a persistent identity reference. The desktop renews within 30 days of expiry, including after expiry when the original private key still exists. A missing/unusable key, or a lost identity reference with existing paired clients, fails closed with a local reset instruction. Older installations that have saved phones but never wrote identity.json require a local reset instead of guessing a certificate from its subject. Never silently trust a replacement key.
- Start/Stop connections is remembered independently of Windows sign-in startup. Normal exit preserves that preference. No trusted network means waiting, with checks on network change and every ten seconds.
- Show selected-PC connection feedback plus per-PC Connected, Available, Offline/searching, or Pairing required. Foreground reads retry automatically; saved selection persists. Revoked credentials require another QR.
- A successful pinned/authenticated status response establishes the selected-PC connection. Failed audio-output, monitor, or shortcut lists show a warning in the affected section and clear that list, without marking the PC offline. Failed device lists retry on the existing ten-second foreground cadence or on manual refresh. Failed status or rejected credentials still disable control; 401 requires pairing.
- Do not replay non-idempotent media, launch, or power-scheduling commands during reconnection.

Protect credentials with Keystore-backed encryption on Android and Keychain on iOS. Credential loss, PC-side revocation, or identity reset requires recovery/pairing. Do not assume app reinstall always removes platform keychain data.

## Multiple PCs

The Android client supports separately selected saved profiles for the user's home desktop and work laptop. The saved certificate fingerprint is the current stable identity; the Android profile also stores a verified identity-key pin that survives normal renewal. Explicit recovery changes the key and re-pairs only the deliberately selected phone profile. Pair each separately. Each profile owns its PC identity, friendly name, endpoint hints, trust pin, and credential. Each PC retains independent paired phones, capabilities, shortcuts, activity, and timers.

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

Do not bypass managed-network policy, disable firewall protections, or expose/forward the command port publicly. Public-network hosting is not enabled automatically. Bluetooth secondary transport is implemented separately from Bluetooth radio on/off. After initial Wi-Fi enrollment and verified Bluetooth metadata, a saved phone can use Bluetooth without LAN reachability. USB, Wi-Fi Direct, and internet relay remain unimplemented. See [Bluetooth](bluetooth.md).

## References

- [Android discovery](https://developer.android.com/develop/connectivity/wifi/use-nsd)
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [Apple Keychain](https://developer.apple.com/documentation/security/adding-a-password-to-the-keychain)
- [OWASP mobile network security](https://mas.owasp.org/MASVS/08-MASVS-NETWORK/)
- [Cisco Meraki isolation](https://documentation.meraki.com/Wireless/Operate_and_Maintain/How_Tos/Firewall_and_Traffic_Shaping/Wireless_Client_Isolation)

## Separate routes and Tailscale

Saved profiles have independent localAddress and tailscaleAddress slots alongside the active address and Bluetooth metadata. Automatic tries local candidates, Tailscale, then Bluetooth; the three Only modes never cross routes. Authenticated status supplies optional networkConnection hints, which are validated as local/Tailscale numeric HTTPS addresses before saving. Each candidate still requires pinned TLS identity before credentials. On a preferred-route recovery probe, an active Bluetooth stream is reused rather than opening a second RFCOMM session. Commands never replay.

Settings > Connection shows the active route, all four preferences and separate Local network address / Tailscale address entries. The editor accepts a bare IP and preserves the known port; Advanced exposes port editing. Exact-endpoint verification precedes saving and preserves the selected preference and other endpoint. Choosing Tailscale only without an address opens setup and selects that preference after successful verification. Bluetooth stays available independently of Wi-Fi/Tailscale and only requires permission when actually used.

Legacy wifi profiles migrate to local or tailscale based on the saved IP; identity and credentials are retained. Missing slots can be learned on the next verified connection. See [Tailscale setup](tailscale.md) for listener behavior, compatibility and firewall scope.