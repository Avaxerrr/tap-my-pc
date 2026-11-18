# Product scope

## Purpose

Control a Windows PC from bed without walking to the computer or using a full remote desktop session. Prioritize quick, deliberate actions on a dark, phone-friendly interface with large controls.

## Agreed platform direction

- Windows host: C# tray application with WPF settings and MVVM.
- Prototype client: responsive website served by the Windows host.
- Final mobile client: Flutter for Android and iOS. Android is the first testing target; the user also owns an iPhone.
- Initial communication: home Wi-Fi/local network. Internet access and a cloud backend are not required.
- Later communication: Bluetooth alongside the mobile app. Protocol and library selection are deferred.

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

## Deferred features

- Presets (including Bedtime) and remote touchpad/keyboard/input are skipped for now at the user's request.
- Remote wake will be revisited with the mobile app and requires hardware/power-state investigation.
- Hardware monitoring is explicitly deferred; preserve PC Stats Tray as a standalone app and website. See [monitoring integration](monitoring-integration.md).
- Other later candidates: display arrangement, media metadata/targeting, and Bluetooth transport. USB networking and internet/VPN/relay support are exploratory options.
- Flutter Android is implemented as a development client; iOS remains planned.

## Mobile requirements and current implementation

- QR first-time pairing; persistent per-PC credentials for normal reconnection.
- Automatic local discovery with identity verification and last-address/manual fallback.
- Home desktop and work laptop profiles from the first mobile version. Pair independently and keep the selected PC visible.
- Remembered host startup after setup, subject to trusted-network restrictions.
- Preserve authentication/revocation. Discovery never authorizes control.
- Saved pairing does not bypass AP isolation or enable internet control.

The Android development client implements QR and manual pinned enrollment, protected saved profiles, automatic discovery/address recovery, remembered PC selection, and multiple independent PCs. Desktop connection startup/pause is remembered and restricted to trusted networks. Existing certificates migrate into stable identity references; automatic certificate renewal/recovery remains unimplemented. See [mobile connections](mobile-connections.md).

## Behavior expectations

- Require deliberate confirmation for shutdown/restart and provide a short cancellation opportunity. Shutdown/restart have a minimum ten-second cancellable delay; other supported power actions have a minimum three seconds.
- Do not force-close applications by default. A power request may be blocked by unsaved work; accepting a command does not guarantee the power transition completes.
- Timers run on the PC and continue when the browser disconnects. The prototype cancels them on process exit and does not persist them across restart.
- Show pending actions and connection failures clearly. Avoid ambiguous toggle commands where an explicit state can be requested, such as setting mute on/off.
- Show immediate sending feedback on the client, command results/errors, and silent non-modal PC notifications. Provide visible power countdowns and cancellation. Keep advanced connection options out of the main setup flow.
- Select the active PC network address automatically. Preserve localhost as a deliberate Advanced debugging option.
- Display-off leaves the PC running; subsequent input or other activity may wake the displays.
- The normal command listener cannot execute while the PC is asleep, hibernating, or shut down. Remote wake is a separate capability.
- Unsupported features should report that they are unavailable rather than appear to succeed.

The desktop displays recently active remote clients on the main connection card and title-bar indicator. While listening without an active client, a muted No phone connected badge distinguishes idle availability from an actual connection. Presence reflects authenticated activity in the last ten seconds; browser traffic and phone availability probes count, including authenticated requests whose operation fails. It is distinct from saved pairing and does not assert which PC is selected for control.

## Desktop personalization

- Dark desktop surfaces with locally saved Blue, Mint, Purple, Teal, or Amber accents. These preferences apply to the desktop dashboard and tray menu, independently of phone clients.
- Drawer transitions, feedback fades, and the visible connection pulse animate independently of Windows visual effects, without an app animation preference.
- Compact default size with expanding cards, two columns on wide windows, natural control heights, and scrollable panels/lists on shorter windows. The custom window shadow is removed for smoother dragging.

## Android presentation

- Match desktop's dark surfaces, Inter typography, modest corner radii, and Blue/Mint/Purple/Teal/Amber accents. Themes persist on the phone independently of the desktop.
- Group controls into Remote, Devices, and Power; keep selected-PC identity and connection feedback visible. PC selection and profile management use focused sheets. Device-list errors must not mark a PC offline when its authenticated status request succeeds; show a specific warning and retain working controls.
- Keep a pending PC action visible across tabs, with a live countdown and cancellation when online. Retain last-known timer information offline without pretending cancellation is available.
- Provide QR-first enrollment, manual fallback, visible version/build metadata, and native permission/failure feedback. Respect large text and compact screens; automatically follow system reduced-motion settings without a separate app animation preference.

## Boundaries

The initial release is for a trusted local network, with authenticated clients. Public internet access, arbitrary remote shell execution, full remote desktop streaming, and a custom Windows driver are outside the initial scope.
