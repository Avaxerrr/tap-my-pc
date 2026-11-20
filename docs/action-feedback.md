# Action feedback and desktop UX

## Implemented behavior

- The web client immediately shows an action-specific sending message and spinner, marks the remote busy, and disables command controls during the request. Success and errors appear in a fixed notification visible even when scrolled away from the header.
- Audio set/mute results include the actual endpoint state read after the operation. Media, display, and native volume-key results say requested/sent rather than claiming the target app or Windows completed an observable transition.
- Power actions require confirmation. Scheduled actions have a countdown and cancellation. On the PC a silent notification appears on scheduling and shows a cancel button for the final ten seconds. Android Lock, Sleep, and Hibernate use immediate request feedback on hosts supporting zero-delay actions.
- Cancellation is available before dispatch. Android shows the last-known scheduled countdown offline with cancellation disabled. When the countdown reaches zero offline, the card hides. The next authenticated status refresh supplies the current timer state.
- The dashboard provides command history in its Activity panel. All clients receive the same bounded in-memory activity feed through status, including the Flutter Android client.

## Desktop presentation

The main screen prioritizes the phone link, host status, pairing, recent activity, and pending power action. Technical settings are collapsed under Advanced. The WPF title bar is frameless using WindowChrome; it retains native caption dragging/resizing and provides minimize, maximize/restore, and hide-to-tray buttons. Interactive maximize/resize behavior still needs manual testing.

`FeedbackWindow` is an app-owned OSD, not a blocking dialog or a Windows toast. It uses a compact 360-DIP dark card with bundled Inter typography, modest corners, an action icon, action title/message, and an explicit phase label. The icon, border, Cancel action button, and countdown progress follow the selected desktop accent live; failures retain a distinct red treatment. The transparent banner uses grayscale text antialiasing. Repeated actions update the same card.

Banners use a brief fade when shown, independently of Windows visual-effects settings; there is no app animation preference. Routine notices remain for about 2.5 seconds and failures for seven seconds. Power countdowns add a Cancel action button and a custom-themed progress bar for the final ten seconds. ShowActivated=false and a WM_MOUSEACTIVATE hook prevent focus stealing. The banner stays out of the taskbar, makes no sound, and remains inside the primary monitor work area. Cancellation can be clicked without activating the banner. Visibility over exclusive-fullscreen games is not guaranteed and has not been tested.

The main-screen notification preference can turn off custom PC notifications. Dashboard history and phone feedback remain available. Display-off commands are recorded and shown on the phone, but the custom overlay is suppressed for successful display-off requests to avoid showing new UI after monitors are told to sleep. Errors still produce a PC notification.

## Windows volume/media overlay

Direct Core Audio volume/mute calls change endpoint state; they do not provide a documented general-purpose instruction to display the shell volume flyout. The app uses direct calls for explicit volume/mute. Normal volume adjustment notices (both slider and relative buttons) are suppressed on the PC; their activity remains visible on the phone and dashboard. Volume errors still show a custom notification. Mute/unmute retains the compact custom notification because direct state changes may not display a Windows flyout.

The relative volume buttons now send VK_VOLUME_UP / VK_VOLUME_DOWN through SendInput, as physical volume keys do. Windows determines step size, native overlay appearance, and timing. Media buttons continue to send media keys. UIPI, an elevated foreground application, shell settings, or exclusive-fullscreen behavior can affect the result. Native overlay behavior must be verified manually; no keypresses were injected during development while the user was gaming.

References: [Core Audio scalar-volume API](https://learn.microsoft.com/en-us/windows/win32/api/endpointvolume/nf-endpointvolume-iaudioendpointvolume-setmastervolumelevelscalar), [virtual keys](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes), [SendInput](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendinput).

## Code ownership

- Core / Feedback: activity models, ordering, bounded history, observer isolation.
- Core / Devices / RemoteCommands: immediate command execution and truthful result messages.
- Core / Timers: scheduled power lifecycle and cancellation.
- Desktop / Features / Feedback: OSD presentation and countdown updates on the WPF Dispatcher.
- Desktop / Features / Settings: dashboard state and preferences.
- Api: transport DTOs and response/status feedback; prototype JavaScript renders progress.

Flutter presentation lives in mobile/lib/ui/ and renders command feedback separately from status polling. No persistent action audit log, sound alerts, Windows Notification Center integration, or media metadata has been added.

## Main-window connection indicator

The main connection card displays a neutral **No phone connected** badge with a disconnected icon while listening without recent authenticated clients. Each active client has a name and a badge for its Bluetooth, Wi-Fi, or Tailscale connection. The badge background and outline identify the transport. Its icon, label, and the phone name use the theme text color. The outer card border uses the selected accent. The title-bar dot uses the chosen accent and pulses while active and visible. Presence reflects authenticated API traffic, including browser requests and availability checks, and expires after ten seconds without activity. Revocation and stopping connections clear it. The pulse stops when the window is hidden or minimized or the connection is idle. Successful authentication counts even if the subsequent operation fails. The custom main-window shadow has been removed for smoother dragging.
