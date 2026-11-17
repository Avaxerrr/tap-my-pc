# Verification

## First prototype checks

Performed on the user's Windows development machine on November 17, 2026, without opening a visible application window or issuing native mutating controls while the user played a game.

- Release solution build: passed with warnings treated as errors.
- Automated suite: 13 tests passed, covering single-use/expired/locked pairing, token persistence as hashes, revocation, timer dispatch/cancellation/conflicts/unsupported states/errors/exit, actual loopback HTTPS hosting, protected commands, static assets, malformed requests, and Origin/Host rejection. Controllers are simulated in these tests.
- Headless installed-Chrome browser smoke: passed pairing, volume/mute, timer scheduling/cancellation, confirmation dismissal, saved-credential reload, and responsive layout at 390-pixel phone width. No JavaScript errors or horizontal overflow were observed. Commands targeted only the isolated simulator.
- WPF settings view: rendered and inspected offscreen without showing or activating a window. This verifies visual construction, not interactive tray behavior or real settings bindings.
- Read-only Windows adapter probe: audio COM access and sleep/hibernate capability queries succeeded. No volume, mute, media, display, or power setting was changed.

Screenshots are generated under `artifacts/screenshots` and are not source-controlled. Browser verification is reproducible through [setup](setup.md#simulator).

## Usability update checks

- Release build: zero warnings/errors; 22 automated tests pass. Added checks cover automatic/manual/stale address selection, no silent localhost fallback, actual audio-state feedback, ordered/bounded activity, observer isolation, honest requested-media semantics, command failure events, timer lifecycle notices, and validated volume-key requests.
- Headless Chrome: confirmed immediate sending notification, spinner, disabled controls/aria-busy during a simulated 800ms request delay, visible error feedback, and a sticky timer/cancel banner, in addition to the existing pairing/control/reload/layout checks.
- Frameless WPF dashboard and custom audio feedback window rendered offscreen and were visually inspected. No window was activated, no overlay was shown, and no actual media/volume/power inputs were sent.
- An isolated offscreen harness also checked legacy settings migration to Automatic, preservation of a new explicit localhost override, actual dashboard binding initialization, pairing-code generation, and cancellation through the dashboard command. It used temporary settings under artifacts and a simulated controller; no user preferences or Windows controls were changed.
- The usability build was staged separately and the user's running original host was left untouched. The update script checks for a running installed copy before copying and was not applied during development. New builds use the TapMyPC name and publish paths following the rename.

Automatic selection rechecks the available private IPs when starting; a network change while the host is already listening still requires stop/start. Custom overlay focus behavior, final-countdown interaction, WindowChrome drag/resize/maximize, and Windows native flyout behavior need real interactive testing.

## TapMyPC rename checks

- Renamed solution/projects/namespaces, dashboard/tray/OSD/web branding, certificate exports, documentation, and executable metadata. The published desktop executable is `TapMyPC.exe`.
- All 22 automated tests pass after the rename; the renamed release publish succeeds.
- Headless browser verification additionally checks that the old browser credential migrates to the TapMyPC storage key and the page title uses TapMyPC.
- An isolated offscreen harness verified fallback reads of old host preferences and paired-phone credentials, plus revocation writing new data without modifying legacy files. Dashboard/feedback views rendered after namespace changes.
- Legacy certificate reuse and already-enabled startup-entry migration are implemented but have not been exercised against the user's actual certificate/registry stores during this rename.

## Still required

- User confirmed phone browser connectivity over Wi-Fi after switching the listener from loopback to the Wi-Fi address. The browser still reports an untrusted certificate; full verification of certificate identity/trust and both Android/iPhone clients remains outstanding. This does not confirm every native control was exercised.
- Interactive WPF settings bindings, tray reopen/exit, paired-client management, and sign-in startup.
- Actual volume/mute, media-key handling, monitor-off, lock/sleep/hibernate/shutdown/restart behavior, and Windows failures/unsaved-work handling.
- Release-host idle CPU and memory measurement. No measured resource claim is made yet.

No firewall rule, startup entry, network-profile change, certificate trust entry, or Wi-Fi listener was enabled by the agent during the initial verification. The user subsequently launched the host and connected a phone. The .NET CLI's first-run setup automatically installed its standard untrusted development certificate; the app's per-address certificates are created when its real host is started.
