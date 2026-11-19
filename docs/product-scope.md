# Product scope

## Purpose

Control a Windows PC from bed without walking to the computer or using a full remote desktop session. Prioritize quick, deliberate actions on a dark, phone-friendly interface with large controls.

## Agreed platform direction

- Windows host: C# tray application with WPF settings and MVVM.
- Prototype client: responsive website served by the Windows host.
- Final mobile client: Flutter for Android and iOS. Android is the first testing target; the user also owns an iPhone.
- Initial communication: home Wi-Fi/local network. Internet access and a cloud backend are not required.
- Communication: Wi-Fi plus a secondary Classic Bluetooth RFCOMM connection on Android. Both use the same pinned HTTPS command API and authorization.

## Initial controls

| Module | Controls and status |
| --- | --- |
| Audio | Read/set volume, volume up/down, mute/unmute, select default output |
| Media | Play/pause, next track, previous track |
| Display | All monitors off; per-monitor brightness and on/off where supported |
| Shortcuts | Launch locally approved apps and websites |
| Bluetooth radio | Read PC Bluetooth status and turn it on/off over Wi-Fi |
| Power | Lock, sleep, hibernate, shutdown, restart |
| Timers | Schedule a supported power action, read remaining time, cancel |
| Status | PC name, connection status, volume/mute, pending timer; current media where available |
| Pairing/settings | Authorize a phone, manage paired clients, view connection details, configure startup preference |

The prototype should include the initial controls before expanding into later features. Build a small end-to-end subset first to verify connectivity and module boundaries.

## Selected additions

Audio output switching, locally approved app/website shortcuts, and per-monitor brightness/on/off are implemented. Hardware support is detected rather than assumed. Display arrangement is outside this pass.

## Next priorities

Updated November 19, 2026.

1. Implemented: certificate renewal/recovery before Bluetooth. Delivery and checks are recorded in [verification](verification.md).
2. Implemented: Bluetooth as a secondary Android connection alongside Wi-Fi, including saved transport choice and physical-link validation. See [Bluetooth](bluetooth.md).
3. Implemented: Android Stats reads the same cached data as the standalone PC Stats Tray dashboard. [Hardware monitoring](monitoring-integration.md)
4. Android supports Wake-on-LAN for a saved PC over local Wi-Fi. The phone learns the adapter MAC and broadcast IPv4 address during a verified connection and shows Wake PC alongside the other Power actions. Manual overrides live in Settings > Wake-on-LAN. The user reported successful TapMyPC wake on the desktop after the Android VPN routing fix. Sleep and hibernate wake were also verified separately with Wolow. See [setup](setup.md#android-wake-on-lan).
5. The in-app Remote Desktop preview for Android provides interactive screen viewing over Wi-Fi and Tailscale, with per-phone access, rotation, landscape fullscreen, Fit and pannable Fill, customizable stream quality, live stream diagnostics, and automatic screen refresh. A separately authorized phone can listen to the default Windows playback output while viewing the desktop. TapMyPC manages the background capture service, viewer password, and common capture settings on Windows. Its dashboard offers setup and, after configuration, shows the service readiness and the active viewer. The target flow is to follow the Windows sign-in screen into the same desktop and continue controlling it after sign-in. Physical verification and an optional home-network relay for away-from-home wake remain planned. See [Remote Desktop prototype](implementation-plan.md#phase-8-remote-desktop--prototype).
6. Media information remains a lower priority.

Certificates automatically renew with the same PC identity key. Updated Android profiles preserve pairing across renewal. A missing or unusable key requires a locally confirmed Reset connection identity, which revokes previous phone credentials and requires re-pairing. Pending PC timers continue during renewal/reset. See [mobile connections](mobile-connections.md) for legacy-profile migration limits.

## Deferred features

- Presets (including Bedtime) and remote touchpad/keyboard/input are skipped for now at the user's request.
- Other later candidates: display arrangement and media metadata/targeting. USB networking and internet/VPN/relay support are exploratory options.
- Flutter Android is implemented as a development client; iOS remains planned.

## Mobile requirements and current implementation

- QR first-time pairing; persistent per-PC credentials for normal reconnection.
- Automatic local discovery with identity verification and last-address/manual fallback.
- Home desktop and work laptop profiles from the first mobile version. Pair independently and keep the selected PC visible.
- Remembered host startup after setup, subject to trusted-network restrictions.
- Preserve authentication/revocation. Discovery never authorizes control.
- Saved pairing does not bypass AP isolation or enable internet control. An already enrolled phone can separately use Bluetooth without a reachable LAN.

The Android development client implements QR and manual pinned enrollment, protected saved profiles, automatic discovery/address recovery, remembered PC selection, multiple independent PCs, and saved Automatic/Wi-Fi-only/Bluetooth-only connection modes. Desktop connection startup/pause is remembered and restricted to trusted networks. Existing certificates migrate into stable identity references; same-key certificate renewal and explicit local identity reset/re-pairing are implemented. See [mobile connections](mobile-connections.md).

## Behavior expectations

- Require confirmation for power actions. Android Lock, Sleep, and Hibernate run immediately on hosts that advertise support. Restart and Shut down retain a ten-second cancellation window. Android scheduled durations accept seconds or minutes with a 24-hour maximum.
- Do not force-close applications by default. A power request may be blocked by unsaved work; accepting a command does not guarantee the power transition completes.
- Timers run on the PC and continue when the browser disconnects. The prototype cancels them on process exit and does not persist them across restart.
- Show pending actions and connection failures clearly. Avoid ambiguous toggle commands where an explicit state can be requested, such as setting mute on/off.
- Show immediate sending feedback on the client, command results/errors, and silent non-modal PC notifications. Provide visible power countdowns and cancellation. Keep advanced connection options out of the main setup flow.
- Select the active PC network address automatically. Preserve localhost as a deliberate Advanced debugging option.
- Display-off leaves the PC running; subsequent input or other activity may wake the displays.
- The normal command listener cannot execute while the PC is asleep, hibernating, or shut down. Remote wake is a separate capability.
- Unsupported features should report that they are unavailable rather than appear to succeed.

The desktop displays recently active remote clients on the main connection card and title-bar indicator. While listening without an active client, a muted No phone connected badge distinguishes idle availability from an actual connection. Presence reflects authenticated activity in the last ten seconds; browser traffic and phone availability probes count, including authenticated requests whose operation fails. It is distinct from saved pairing and does not assert which PC is selected for control.

## Phone identity and radio presentation

- The Windows connection card shows each active phone's OS name, model, or locally saved name and a badge for its latest authenticated connection. Bluetooth is blue, Wi-Fi is green, and Tailscale is purple. The card also shows listener readiness.
- Existing Android pairings update their reported name through authenticated traffic without re-pairing. PC-side names can be edited in Configure > Authorized phones and take precedence over reported names.
- Mobile shows PC Bluetooth: On/Off. Over Wi-Fi it offers only the applicable action; unavailable/unknown/mixed state disables changes. Radio changes are disabled while actually connected over Bluetooth, including Automatic fallback, with a switch-to-Wi-Fi explanation. The Bluetooth API listener enforces the same restriction.

## Desktop personalization

- Desktop themes include Dark, Light, Midnight, Forest, and Plum, with independently chosen Blue, Mint, Purple, Teal, or Amber accents. The saved choices apply to the desktop dashboard, tray menu, and command feedback banners.
- Drawer transitions, feedback fades, and the visible connection pulse animate independently of Windows visual effects, without an app animation preference.
- Compact default size with expanding cards, two columns on wide windows, natural control heights, and scrollable panels/lists on shorter windows. The custom window shadow is removed for smoother dragging.

## Android presentation

- Match desktop's dark surfaces, Inter typography, modest corner radii, and Blue/Mint/Purple/Teal/Amber accents. Themes persist on the phone independently of the desktop.
- Group controls into Remote, Devices, and Power. Show hardware monitoring in Stats. Keep selected-PC identity and connection feedback visible. PC selection and profile management use focused sheets. Device-list errors must not mark a PC offline when its authenticated status request succeeds; show a specific warning and retain working controls.
- Keep a pending PC action visible across tabs, with a live countdown and cancellation when online. Show the last-known countdown offline until it is due, then reconcile with the PC when it reconnects.
- Provide a focused first-connection card with one Add your PC action, QR-first enrollment, manual fallback, version/build metadata in Settings > About, and native permission/failure feedback. Respect large text and compact screens; automatically follow system reduced-motion settings without a separate app animation preference.

## Boundaries

The initial release is for a trusted local network, with authenticated clients. Direct private remote access through an optional Tailscale listener alongside LAN is supported, with separate saved mobile endpoints and explicit/automatic route choices; see [Tailscale setup](tailscale.md). Public internet hosting, arbitrary remote shell execution, and a custom Windows driver are outside the initial scope.
