import 'package:flutter/material.dart';
import '../connection.dart';
import 'app_theme.dart';
import 'widgets.dart';
import 'remote_controls.dart';
import 'pending_banner.dart';
import 'pc_welcome.dart';

class RemoteDashboard extends StatefulWidget {
  final List<PcProfile> profiles;
  final PcProfile? selected;
  final Map<String, dynamic>? status, pending;
  final String message, appVersion, discoveryMessage;
  final String? feedback, serverTime;
  final bool busy, feedbackError;
  final bool usingBluetooth;
  final List<dynamic> outputs, monitors, shortcuts;
  final Map<String, String> deviceErrors;
  final String Function(PcProfile) profileStatus;
  final ValueChanged<PcProfile> onSelect;
  final Future<void> Function() onAdd, onForget, onRefresh;
  final Future<void> Function()? onRecover, onConnection;
  final VoidCallback onHelp;
  final SendCommand send;
  final PowerCommand power;
  final Future<void> Function(bool) onBluetooth;
  final ValueChanged<double> onVolumePreview;
  final void Function(String, double) onBrightnessPreview;
  const RemoteDashboard({
    super.key,
    required this.profiles,
    required this.selected,
    required this.status,
    required this.message,
    required this.appVersion,
    required this.discoveryMessage,
    required this.busy,
    required this.outputs,
    required this.monitors,
    required this.shortcuts,
    required this.profileStatus,
    required this.onSelect,
    required this.onAdd,
    required this.onForget,
    this.onRecover,
    this.usingBluetooth = false,
    this.onConnection,
    required this.onRefresh,
    required this.onHelp,
    required this.send,
    required this.power,
    required this.onBluetooth,
    required this.onVolumePreview,
    required this.onBrightnessPreview,
    this.deviceErrors = const {},
    this.feedback,
    this.feedbackError = false,
    this.pending,
    this.serverTime,
  });
  @override
  State<RemoteDashboard> createState() => _RemoteDashboardState();
}

class _RemoteDashboardState extends State<RemoteDashboard> {
  int tab = 0;
  Future<void> choosePc() => showAppSheet(
    context,
    title: 'Your PCs',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Commands always go to the selected PC.',
          style: TextStyle(color: AppColors.secondary),
        ),
        const SizedBox(height: 12),
        for (final profile in widget.profiles)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.desktop_windows_outlined),
            title: Text(profile.name),
            subtitle: Text(widget.profileStatus(profile)),
            trailing: profile.pin == widget.selected?.pin
                ? Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
            onTap: widget.busy
                ? null
                : () {
                    Navigator.pop(context);
                    widget.onSelect(profile);
                  },
          ),
        const Divider(),
        FilledButton.icon(
          onPressed: widget.busy
              ? null
              : () {
                  Navigator.pop(context);
                  widget.onAdd();
                },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add another PC'),
        ),
      ],
    ),
  );
  Future<void> settings() async {
    final appearance = AppearanceScope.of(context);
    await showAppSheet(
      context,
      title: 'Settings',
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('APPEARANCE', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            const Text(
              'Accent color',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final palette in AccentPalette.choices)
                  Semantics(
                    selected: palette.name == appearance.palette.name,
                    child: Tooltip(
                      message: palette.name,
                      child: OutlinedButton(
                        onPressed: () => appearance.setAccent(palette),
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              palette.name == appearance.palette.name
                              ? palette.soft
                              : AppColors.elevated,
                          side: BorderSide(
                            color: palette.name == appearance.palette.name
                                ? palette.fill
                                : AppColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: palette.fill,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(palette.name),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Match the desktop palette. This phone’s appearance is saved independently.',
              style: TextStyle(color: AppColors.secondary, fontSize: 12),
            ),
            if (appearance.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  appearance.error,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            const Divider(),
            Text('CONNECTIONS', style: Theme.of(context).textTheme.bodySmall),
            if (widget.selected != null && widget.onConnection != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.settings_input_antenna),
                title: const Text('Connection'),
                subtitle: Text(
                  widget.selected!.connectionMode == 'auto'
                      ? 'Automatic · Wi-Fi first'
                      : widget.selected!.connectionMode == 'bluetooth'
                      ? 'Bluetooth only'
                      : 'Wi-Fi only',
                ),
                onTap: widget.busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onConnection!();
                      },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add),
              title: const Text('Add a PC'),
              onTap: widget.busy
                  ? null
                  : () {
                      Navigator.pop(context);
                      widget.onAdd();
                    },
            ),
            if (widget.selected != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.refresh),
                title: const Text('Refresh devices'),
                onTap: widget.busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onRefresh();
                      },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.link_off, color: AppColors.error),
                title: const Text(
                  'Forget selected PC',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: widget.busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onForget();
                      },
              ),
            ],
            if (widget.selected != null && widget.onRecover != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Re-pair selected PC'),
                onTap: widget.busy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onRecover!();
                      },
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.help_outline),
              title: const Text('Connection help'),
              onTap: () {
                Navigator.pop(context);
                widget.onHelp();
              },
            ),
            Text(
              widget.discoveryMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.selected != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SelectableText(
                  widget.selected!.address,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(),
            Text('ABOUT TAPMYPC', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),

            Text(
              widget.appVersion.isEmpty
                  ? 'Reading installed version…'
                  : widget.appVersion,
              key: const Key('about-version'),
            ),
            if (widget.status?['serverVersion'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'PC v${widget.status!['serverVersion']}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> activity() => showAppSheet(
    context,
    title: 'Recent activity',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((widget.status?['activity'] as List? ?? []).isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'Commands and their results will appear here.',
              style: TextStyle(color: AppColors.secondary),
            ),
          ),
        for (final item in widget.status?['activity'] ?? [])
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['message'] ?? '',
                  style: TextStyle(
                    color: item['phase'] == 'Failed'
                        ? AppColors.error
                        : AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item['phase'] ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final connected = widget.status != null;
    final largeText = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.4;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: widget.profiles.isEmpty
            ? (largeText ? 80 : 64)
            : (largeText ? 96 : 72),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TapMyPC',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
            if (widget.profiles.isNotEmpty)
              Text(
                widget.appVersion.isEmpty
                    ? 'Reading version…'
                    : widget.appVersion,
                key: const Key('app-version'),
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.secondary,
                ),
              ),
          ],
        ),
        actions: [
          if (widget.selected != null)
            IconButton(
              onPressed: activity,
              tooltip: 'Recent activity',
              icon: const Icon(Icons.history_outlined, size: 21),
            ),
          IconButton(
            onPressed: widget.onHelp,
            tooltip: 'How connections work',
            icon: const Icon(Icons.help_outline, size: 21),
          ),
          IconButton(
            onPressed: settings,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 21),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.selected != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: widget.busy ? null : choosePc,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'YOUR PC',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  StatusBadge(
                                    text: connected
                                        ? 'Connected'
                                        : widget.busy
                                        ? 'Working'
                                        : 'Offline',
                                    connected: connected,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.desktop_windows_outlined,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      widget.selected!.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ),
                                  const Icon(
                                    Icons.keyboard_arrow_down,
                                    size: 20,
                                    color: AppColors.secondary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 7),
                              Text(
                                widget.message,
                                key: const Key('connection-status'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.busy || widget.feedback != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Semantics(
                      liveRegion: true,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.busy)
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else
                            Icon(
                              widget.feedbackError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              size: 16,
                              color: widget.feedbackError
                                  ? AppColors.error
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer,
                            ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              widget.busy
                                  ? 'Sending to ${widget.selected?.name ?? 'PC'}…'
                                  : widget.feedback!,
                              style: TextStyle(
                                fontSize: 12,
                                color: widget.feedbackError
                                    ? AppColors.error
                                    : AppColors.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: widget.onRefresh,
                    child: ListView(
                      key: PageStorageKey('controls-$tab'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (widget.profiles.isEmpty) ...[
                          const SizedBox(height: 20),
                          PcWelcome(
                            onAdd: widget.busy ? null : widget.onAdd,
                            message: widget.message,
                          ),
                        ] else if (widget.selected != null) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                            child: Text(
                              [
                                'EVERYDAY CONTROLS',
                                'DISPLAYS & CONNECTIONS',
                                'POWER & TIMERS',
                              ][tab],
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontSize: 10.5, letterSpacing: 1),
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                for (final child in previous)
                                  ExcludeSemantics(
                                    child: IgnorePointer(child: child),
                                  ),
                                ?current,
                              ],
                            ),
                            child: KeyedSubtree(
                              key: ValueKey(tab),
                              child: switch (tab) {
                                0 => RemoteControls(
                                  status: widget.status,
                                  outputsError:
                                      widget.deviceErrors['/audio/outputs'],
                                  shortcutsError:
                                      widget.deviceErrors['/shortcuts'],
                                  outputs: widget.outputs,
                                  shortcuts: widget.shortcuts,
                                  busy: widget.busy,
                                  send: widget.send,
                                  onVolumePreview: widget.onVolumePreview,
                                ),
                                1 => DeviceControls(
                                  usingBluetooth: widget.usingBluetooth,
                                  status: widget.status,
                                  monitorsError:
                                      widget.deviceErrors['/monitors'],
                                  monitors: widget.monitors,
                                  busy: widget.busy,
                                  send: widget.send,
                                  onBluetooth: widget.onBluetooth,
                                  onBrightnessPreview:
                                      widget.onBrightnessPreview,
                                ),
                                _ => PowerControls(
                                  status: widget.status,
                                  busy: widget.busy,
                                  power: widget.power,
                                ),
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.profiles.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.pending != null)
                  PendingActionBanner(
                    pending: widget.pending!,
                    serverTime: widget.serverTime,
                    pcName: widget.selected?.name ?? 'PC',
                    onCancel: !widget.busy && connected
                        ? () => widget.send(
                            '/power/${widget.pending!['id']}',
                            'DELETE',
                            null,
                          )
                        : null,
                  ),
                NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (value) => setState(() => tab = value),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: 'Remote',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.devices_outlined),
                      selectedIcon: Icon(Icons.devices),
                      label: 'Devices',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.power_settings_new),
                      label: 'Power',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
