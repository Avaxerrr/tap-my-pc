# Action feedback and desktop UX

## Implemented behavior

- The web client immediately shows an action-specific sending message and spinner, marks the remote busy, and disables command controls during the request. Success and errors appear in a fixed notification visible even when scrolled away from the header.
- Audio set/mute results include the actual endpoint state read after the operation. Media, display, and native volume-key results say requested/sent rather than claiming the target app or Windows completed an observable transition.
- Power actions still require confirmation. Both interfaces show a pending countdown and cancellation. On the PC a silent, non-modal notification appears for scheduling, and the final ten seconds remain visible with a cancel button. The website keeps a sticky countdown banner.
- Cancellation means a pending timer was removed before dispatch. Once dispatch begins, neither interface promises cancellation. If a scheduled action disconnects the PC, the phone says the action may have started and cannot confirm completion.
- The dashboard shows a small recent-activity list. All clients receive the same bounded in-memory activity feed through status, so the behavior is reusable by Flutter.

## Desktop presentation

The main screen prioritizes the phone link, host status, pairing, recent activity, and pending power action. Technical settings are collapsed under Advanced. The WPF title bar is frameless using WindowChrome; it retains native caption dragging/resizing and provides minimize, maximize/restore, and hide-to-tray buttons. Interactive maximize/resize behavior still needs manual testing.

`FeedbackWindow` is an app-owned OSD, not a blocking dialog or a Windows toast. Routine notifications now use a compact 320-pixel card with an action icon, small caption, and message; repeated actions update the same card. They fade in without activating and remain for about three seconds; errors use a red icon and remain for seven seconds. Power countdowns add a Cancel button and a progress bar for the final ten seconds. It uses ShowActivated=false plus a WM_MOUSEACTIVATE hook that refuses activation. It stays out of the taskbar, makes no sound, and is positioned inside the primary monitor work area. Its cancellation button can be clicked without activating it. Visibility over exclusive-fullscreen games is not guaranteed and has not been tested.

Advanced settings can turn off custom PC notifications. Dashboard history and phone feedback remain available. Display-off commands are recorded and shown on the phone, but the custom overlay is suppressed for successful display-off requests to avoid showing new UI after monitors are told to sleep. Errors still produce a PC notification.

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

No persistent action audit log, sound alerts, Windows Notification Center integration, media metadata, or Flutter presentation has been added.
