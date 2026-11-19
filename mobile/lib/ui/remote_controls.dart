import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'widgets.dart';

typedef SendCommand =
    Future<void> Function(String path, String method, Object? body);
typedef PowerCommand = Future<void> Function(String action, {int? delay});

class RemoteControls extends StatelessWidget {
  final Map<String, dynamic>? status;
  final List<dynamic> outputs, shortcuts;
  final String? outputsError, shortcutsError;
  final bool busy;
  final SendCommand send;
  final ValueChanged<double> onVolumePreview;
  const RemoteControls({
    super.key,
    required this.status,
    required this.outputs,
    required this.shortcuts,
    required this.busy,
    required this.send,
    required this.onVolumePreview,
    this.outputsError,
    this.shortcutsError,
  });
  @override
  Widget build(BuildContext context) {
    final audio = status?['audio'];
    final available = !busy && status != null;
    final canAudio =
        available && audio != null && status?['capabilities']?['audio'] == true;
    final canMedia = available && status?['capabilities']?['media'] == true;
    final muted = audio?['muted'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Sound',
          subtitle: audio == null
              ? 'Audio is unavailable on this PC'
              : muted
              ? 'Muted'
              : 'Set the room to your volume',
          trailing: Text(
            audio == null ? '—' : '${audio['volume']}%',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Slider(
                semanticFormatterCallback: (value) =>
                    '${value.round()} percent',
                value: ((audio?['volume'] ?? 0) as num).toDouble().clamp(
                  0,
                  100,
                ),
                min: 0,
                max: 100,
                onChanged: canAudio ? onVolumePreview : null,
                onChangeEnd: canAudio
                    ? (value) => send('/audio/volume', 'PUT', {
                        'volume': value.round(),
                      })
                    : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: canAudio
                          ? () => send('/audio/step', 'POST', {
                              'direction': 'Down',
                            })
                          : null,
                      child: const Icon(
                        Icons.volume_down_outlined,
                        semanticLabel: 'Volume down',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: canAudio
                          ? () => send('/audio/mute', 'PUT', {'muted': !muted})
                          : null,
                      icon: Icon(
                        muted
                            ? Icons.volume_off_outlined
                            : Icons.volume_up_outlined,
                        size: 18,
                      ),
                      label: Text(muted ? 'Unmute' : 'Mute'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: canAudio
                          ? () =>
                                send('/audio/step', 'POST', {'direction': 'Up'})
                          : null,
                      child: const Icon(
                        Icons.volume_up_outlined,
                        semanticLabel: 'Volume up',
                      ),
                    ),
                  ),
                ],
              ),
              if (outputsError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    outputsError!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: available && outputs.isNotEmpty
                    ? () => showAppSheet(
                        context,
                        title: 'Audio output',
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final output in outputs)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.speaker_outlined),
                                title: Text(output['name']),
                                trailing: output['isDefault'] == true
                                    ? Icon(
                                        Icons.check,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      )
                                    : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  send('/audio/output', 'PUT', {
                                    'id': output['id'],
                                  });
                                },
                              ),
                          ],
                        ),
                      )
                    : null,
                icon: const Icon(Icons.speaker_outlined, size: 18),
                label: Text(
                  outputs
                          .where((o) => o['isDefault'] == true)
                          .firstOrNull?['name'] ??
                      'Audio output',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Media',
          subtitle: 'Playback on this PC',
          child: Row(
            children: [
              Expanded(
                child: IconButton.outlined(
                  tooltip: 'Previous track',
                  onPressed: canMedia
                      ? () => send('/media', 'POST', {'action': 'Previous'})
                      : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: canMedia
                      ? () => send('/media', 'POST', {'action': 'PlayPause'})
                      : null,
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    semanticLabel: 'Play or pause',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: IconButton.outlined(
                  tooltip: 'Next track',
                  onPressed: canMedia
                      ? () => send('/media', 'POST', {'action': 'Next'})
                      : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Shortcuts',
          subtitle: 'Approved on your PC',
          child: shortcutsError != null
              ? Text(
                  shortcutsError!,
                  style: const TextStyle(color: AppColors.error),
                )
              : shortcuts.isEmpty
              ? const Text(
                  'Add apps and websites in the PC app’s Configure panel, then refresh here.',
                  style: TextStyle(color: AppColors.secondary),
                )
              : ActionGrid(
                  children: [
                    for (final shortcut in shortcuts)
                      ActionTile(
                        label: shortcut['name'],
                        icon: shortcut['kind'] == 'Website'
                            ? Icons.language_outlined
                            : Icons.open_in_new,
                        onPressed: available
                            ? () => send(
                                '/shortcuts/${shortcut['id']}/launch',
                                'POST',
                                {},
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class DeviceControls extends StatelessWidget {
  final bool usingBluetooth;
  final Map<String, dynamic>? status;
  final List<dynamic> monitors;
  final String? monitorsError;
  final bool busy;
  final SendCommand send;
  final Future<void> Function(bool) onBluetooth;
  final void Function(String, double) onBrightnessPreview;
  const DeviceControls({
    super.key,
    this.usingBluetooth = false,
    required this.status,
    required this.monitors,
    required this.busy,
    required this.send,
    required this.onBluetooth,
    required this.onBrightnessPreview,
    this.monitorsError,
  });
  @override
  Widget build(BuildContext context) {
    final available = !busy && status != null;
    final bluetooth = status?['bluetooth'];
    final radioState = bluetooth?['state'] as String?;
    final knownState = radioState == 'On' || radioState == 'Off';
    final radioEnabled = radioState == 'On';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Displays',
          subtitle: 'Leave the PC running, turn the screens off',
          child: ActionTile(
            label: 'Turn all screens off',
            icon: Icons.desktop_windows_outlined,
            onPressed: available && status?['capabilities']?['display'] == true
                ? () => send('/display/off', 'POST', {})
                : null,
          ),
        ),
        if (monitors.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              monitorsError ??
                  'Individual display controls appear here when supported.',
              style: TextStyle(color: AppColors.secondary),
            ),
          ),
        for (final monitor in monitors)
          SectionCard(
            title: monitor['name'],
            subtitle: monitor['brightness'] == null
                ? 'Brightness unavailable'
                : 'Brightness · ${monitor['brightness']}%',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Slider(
                  value: ((monitor['brightness'] ?? 50) as num)
                      .toDouble()
                      .clamp(0, 100),
                  min: 0,
                  max: 100,
                  semanticFormatterCallback: (value) =>
                      '${value.round()} percent brightness',
                  onChanged: available && monitor['canSetBrightness'] == true
                      ? (v) => onBrightnessPreview(monitor['id'], v)
                      : null,
                  onChangeEnd: available && monitor['canSetBrightness'] == true
                      ? (v) => send('/monitors/brightness', 'PUT', {
                          'id': monitor['id'],
                          'brightness': v.round(),
                        })
                      : null,
                ),
                ActionGrid(
                  children: [
                    for (final enabled in [true, false])
                      ActionTile(
                        label: enabled ? 'Turn on' : 'Turn off',
                        icon: enabled
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        onPressed: available && monitor['canSetPower'] == true
                            ? () => send('/monitors/power', 'PUT', {
                                'id': monitor['id'],
                                'enabled': enabled,
                              })
                            : null,
                      ),
                  ],
                ),
                if (monitor['message'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      monitor['message'],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        SectionCard(
          title: 'Bluetooth',
          subtitle: 'PC Bluetooth: ${radioState ?? 'Unavailable'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                usingBluetooth
                    ? 'Switch to local network or Tailscale to change the PC’s Bluetooth.'
                    : 'Control the PC’s Bluetooth radio over local network or Tailscale.',
                style: TextStyle(color: AppColors.secondary),
              ),
              const SizedBox(height: 14),
              if (knownState)
                ActionTile(
                  label: radioEnabled ? 'Turn off' : 'Turn on',
                  icon: radioEnabled
                      ? Icons.bluetooth_disabled
                      : Icons.bluetooth,
                  onPressed:
                      available &&
                          !usingBluetooth &&
                          bluetooth?['canControl'] == true
                      ? () => onBluetooth(!radioEnabled)
                      : null,
                )
              else
                const Text(
                  'Bluetooth controls are unavailable until the PC reports an On or Off state.',
                  style: TextStyle(color: AppColors.secondary),
                ),
              if (bluetooth?['message'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    bluetooth['message'],
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class PowerControls extends StatelessWidget {
  final Map<String, dynamic>? status;
  final bool busy;
  final PowerCommand power;
  final VoidCallback? onWake;
  const PowerControls({
    super.key,
    required this.status,
    required this.busy,
    required this.power,
    this.onWake,
  });
  bool supports(String action) =>
      !busy &&
      status != null &&
      (action == 'Sleep'
          ? status?['capabilities']?['sleep'] == true
          : action == 'Hibernate'
          ? status?['capabilities']?['hibernate'] == true
          : true);
  static const icons = {
    'Lock': Icons.lock_outline,
    'Sleep': Icons.bedtime_outlined,
    'Hibernate': Icons.nights_stay_outlined,
    'Shutdown': Icons.power_settings_new,
    'Restart': Icons.restart_alt,
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionCard(
        title: 'Power',
        child: ActionGrid(
          children: [
            for (final action in icons.entries)
              ActionTile(
                label: action.key == 'Shutdown' ? 'Shut down' : action.key,
                icon: action.value,
                danger: ['Shutdown', 'Restart'].contains(action.key),
                onPressed: supports(action.key)
                    ? () => power(action.key)
                    : null,
              ),
            ActionTile(
              label: 'Wake PC',
              icon: Icons.power_settings_new,
              onPressed: status == null && !busy ? onWake : null,
            ),
          ],
        ),
      ),
      SectionCard(
        title: 'Set a timer',
        subtitle: 'The PC keeps time, even if this phone disconnects',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'AFTER 30 MINUTES',
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final action in ['Sleep', 'Hibernate', 'Shutdown'])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActionTile(
                  label: action == 'Shutdown' ? 'Shut down' : action,
                  icon: icons[action]!,
                  onPressed: supports(action)
                      ? () => power(action, delay: 1800)
                      : null,
                ),
              ),
          ],
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          'Unsaved work may prevent a power action. Apps are not force-closed.',
          style: TextStyle(color: AppColors.secondary, fontSize: 12),
        ),
      ),
    ],
  );
}
