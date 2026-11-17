# Mobile connections and trust

Status: planned Flutter design, November 18, 2026. QR pairing, automatic discovery, stable PC identity, protected mobile storage, multi-PC profiles, and remembered host startup are not implemented yet. Monitoring is deferred and does not block mobile work.

## Current prototype

The browser uses a manual HTTPS address and a single-use six-digit pairing code. Pairing creates a persistent per-client bearer credential; the PC stores its hash and supports revocation. Reconnects do not inherently require another code. Browser credentials are origin-bound, so an address change affects access to saved browser storage.

Normal desktop launch leaves the host stopped. Certificates are generated per address. These behaviors need deliberate migration for the mobile flow.

## First connection

1. User opens Add phone locally on the intended PC.
2. Desktop shows a short-lived QR containing protocol version, stable PC ID, endpoint hints, PC public-key identity, and a strong random single-use pairing secret.
3. Phone verifies the scanned PC identity before transmitting that secret.
4. PC atomically consumes the secret and issues a separate persistent credential for this phone.
5. Phone saves the profile and credential in platform-protected storage.

The QR is sensitive while valid, requires access to the displayed pairing screen, and contains no permanent command credential. Secrets expire and are never advertised through discovery or logged. Keep a manual fallback; its trust-verification UI needs design rather than blindly accepting discovered endpoints.

## Normal operation

- Discover saved PCs with mDNS/DNS-SD; try last-known/manual addresses as fallbacks.
- Treat discovered names, IDs, and addresses as untrusted hints. Verify saved cryptographic identity before sending credentials or commands.
- Authenticate silently per PC; ordinary restarts, IP changes, and temporary disconnections do not require new enrollment.
- Make identity independent of IP. Migrate current per-address certificates and explicitly handle renewal, key replacement, and recovery. Never silently trust a replacement key.
- Offer remembered Start host when TapMyPC opens with trusted-network restrictions, separate from Windows sign-in startup.
- Report Offline, Connecting, Connected, Permission needed, or Pairing required accurately.
- Do not replay non-idempotent media, launch, or power-scheduling commands during reconnection.

Protect credentials with Keystore-backed encryption on Android and Keychain on iOS. Credential loss, PC-side revocation, or identity reset requires recovery/pairing. Do not assume app reinstall always removes platform keychain data.

## Multiple PCs

Support the user's home desktop and work laptop from the first mobile version. Pair each separately. Each profile owns its PC identity, friendly name, endpoint hints, trust pin, and credential. Each PC retains independent paired phones, capabilities, shortcuts, activity, and timers.

Keep selected PC visible, especially in power confirmations. Switching profiles must isolate responses and in-flight work. Never redirect commands or silently fall back to another PC. Future monitoring availability is per PC.

## Security and validation

This is a reasonable design to implement, not a completed mobile implementation or security audit. Persistent pairing is compatible with secure operation when credentials are protected, PC identity is verified on every connection, and credentials remain revocable.

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
