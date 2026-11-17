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
| Audio | Read/set volume, volume up/down, mute/unmute |
| Media | Play/pause, next track, previous track |
| Display | Turn monitors off |
| Power | Lock, sleep, hibernate, shutdown, restart |
| Timers | Schedule a supported power action, read remaining time, cancel |
| Status | PC name, connection status, volume/mute, pending timer; current media where available |
| Pairing/settings | Authorize a phone, manage paired clients, view connection details, configure startup preference |

The prototype should include the initial controls before expanding into later features. Build a small end-to-end subset first to verify connectivity and module boundaries.

## Next features

- Configurable presets, especially Bedtime: pause media, mute, turn displays off, and hibernate after a delay.
- Select an audio output device such as speakers or headphones.
- Launch explicitly approved applications and open selected websites.

## Later candidates

- Monitor brightness, individual monitor selection, and display arrangement, subject to hardware support.
- Remote touchpad, keyboard, scrolling, and selected shortcuts.
- Multiple PCs.
- Wake-on-LAN/Wake on Wireless LAN, subject to hardware and power-state support.
- Bluetooth transport, including Android/iPhone compatibility verification.

These candidates are not commitments for the first prototype.

## Behavior expectations

- Require deliberate confirmation for shutdown/restart and provide a short cancellation opportunity. Exact interaction and duration remain to be selected.
- Do not force-close applications by default. A power request may be blocked by unsaved work; accepting a command does not guarantee the power transition completes.
- Timers run on the PC and continue when the browser disconnects. The prototype cancels them on process exit and does not persist them across restart.
- Show pending actions and connection failures clearly. Avoid ambiguous toggle commands where an explicit state can be requested, such as setting mute on/off.
- Show immediate sending feedback on the client, command results/errors, and silent non-modal PC notifications. Provide visible power countdowns and cancellation. Keep advanced connection options out of the main setup flow.
- Select the active PC network address automatically. Preserve localhost as a deliberate Advanced debugging option.
- Display-off leaves the PC running; subsequent input or other activity may wake the displays.
- The normal command listener cannot execute while the PC is asleep, hibernating, or shut down. Remote wake is a separate capability.
- Unsupported features should report that they are unavailable rather than appear to succeed.

## Boundaries

The initial release is for a trusted local network, with authenticated clients. Public internet access, arbitrary remote shell execution, full remote desktop streaming, and a custom Windows driver are outside the initial scope.
