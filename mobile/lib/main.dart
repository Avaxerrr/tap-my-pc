import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'connection.dart';
import 'pairing_page.dart';
import 'discovery.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TapMyPcApp());
}

class TapMyPcApp extends StatelessWidget {
  const TapMyPcApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TapMyPC',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffc9efaa),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xff101718),
      cardTheme: const CardThemeData(
        color: Color(0xff192325),
        margin: EdgeInsets.only(bottom: 16),
      ),
    ),
    home: const RemotePage(),
  );
}

class RemotePage extends StatefulWidget {
  const RemotePage({super.key});
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> with WidgetsBindingObserver {
  final store = const ProfileStore();
  List<PcProfile> profiles = [];
  PcProfile? selected;
  PcApi? api;
  Map<String, dynamic>? status;
  List<dynamic> outputs = [], monitors = [], shortcuts = [];
  String message = 'Add your first PC to get started.';
  bool busy = false, refreshing = false, foreground = true;
  String appVersion = '';
  int epoch = 0;
  Timer? timer;
  StreamSubscription<Map<dynamic, dynamic>>? discoverySubscription;
  final Map<String, List<String>> candidates = {};
  final Map<String, DateTime> verifiedAt = {};
  final Set<String> pairingRequired = {};
  String discoveryMessage = 'Looking for saved PCs on this network.';
  bool probing = false;
  int ticks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    loadVersion();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      refresh();
      if (++ticks % 5 == 0) probeSaved();
    });
  }

  Future<void> loadVersion() async {
    try {
      final info = await const MethodChannel(
        'dev.tapmypc/app',
      ).invokeMapMethod<String, dynamic>('version');
      if (mounted && info != null) {
        setState(
          () => appVersion = 'v${info['version']} (build ${info['build']})',
        );
      }
    } catch (_) {
      if (mounted) setState(() => appVersion = 'Version unavailable');
    }
  }

  Future<void> load() async {
    try {
      final saved = await store.load();
      if (!mounted) return;
      setState(() => profiles = saved);
      final preferred = await store.lastSelected();
      if (!mounted) return;
      if (saved.isNotEmpty) {
        select(
          saved.where((p) => normalizePin(p.pin) == preferred).firstOrNull ??
              saved.first,
        );
        startDiscovery();
        unawaited(probeSaved());
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Could not unlock saved PCs. Try restarting the app.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) {
      startDiscovery();
      refresh();
      unawaited(probeSaved());
    } else {
      stopDiscovery();
    }
  }

  void select(PcProfile profile) {
    epoch++;
    api?.close();
    api = PcApi(profile);
    setState(() {
      selected = profile;
      status = null;
      outputs = [];
      monitors = [];
      shortcuts = [];
      message = 'Connecting to ${profile.name}…';
    });
    unawaited(store.select(profile.pin).catchError((Object _) {}));
    refresh(devices: true);
  }

  Future<void> refresh({bool devices = false}) async {
    final client = api;
    final generation = epoch;
    if (client == null ||
        busy ||
        refreshing ||
        !foreground ||
        pairingRequired.contains(selected?.pin)) {
      return;
    }
    refreshing = true;
    try {
      Map<String, dynamic> next;
      try {
        next = Map<String, dynamic>.from(await client.request('/status'));
      } catch (initialError) {
        if (!mounted || generation != epoch) return;
        if (initialError is PcApiException && initialError.statusCode == 401) {
          rethrow;
        }
        final current = selected!;
        final alternatives = (candidates[normalizePin(current.pin)] ?? [])
            .where((a) => a != current.address);
        if (alternatives.isEmpty) rethrow;
        final recovered = await reconnectPc(current, alternatives);
        if (!mounted || generation != epoch) {
          recovered.api.close();
          return;
        }
        api?.close();
        api = recovered.api;
        final updated = recovered.profile;
        setState(() {
          profiles = profiles
              .map(
                (p) => normalizePin(p.pin) == normalizePin(updated.pin)
                    ? updated
                    : p,
              )
              .toList();
          selected = updated;
        });
        try {
          await store.save(profiles);
        } catch (_) {
          /* Current verified connection remains usable. */
        }
        next = recovered.status;
      }
      if (!mounted || generation != epoch) return;
      final activeClient = api!;
      List<dynamic>? newOutputs, newMonitors, newShortcuts;
      if (devices || status == null) {
        final lists = await Future.wait([
          activeClient.request('/audio/outputs'),
          activeClient.request('/monitors'),
          activeClient.request('/shortcuts'),
        ]);
        newOutputs = lists[0] as List;
        newMonitors = lists[1] as List;
        newShortcuts = lists[2] as List;
      }
      if (!mounted || generation != epoch) return;
      setState(() {
        status = next;
        verifiedAt[normalizePin(selected!.pin)] = DateTime.now();
        if (newOutputs != null) outputs = newOutputs;
        if (newMonitors != null) monitors = newMonitors;
        if (newShortcuts != null) shortcuts = newShortcuts;
        message = 'Connected to ${selected!.name}';
      });
    } catch (error) {
      if (mounted && generation == epoch) {
        setState(() {
          status = null;
          if (error is PcApiException && error.statusCode == 401) {
            pairingRequired.add(selected!.pin);
            message = 'Pairing required. Scan a new QR on ${selected!.name}.';
          } else {
            message = 'Connection unavailable. ${friendly(error)}';
          }
        });
      }
    } finally {
      refreshing = false;
      if (mounted && generation != epoch) refresh(devices: true);
    }
  }

  String friendly(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
  Future<void> command(String path, String method, Object? body) async {
    if (busy || status == null || api == null) return;
    final generation = epoch;
    final client = api!;
    setState(() {
      busy = true;
      message = 'Sending to ${selected!.name}…';
    });
    try {
      final result = await client.request(path, method: method, body: body);
      if (!mounted || generation != epoch) return;
      final text =
          result['feedback']?['message'] ??
          (method == 'DELETE' ? 'Timer canceled' : 'Action scheduled');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
    } catch (error) {
      if (mounted && generation == epoch) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${friendly(error)} No automatic retry was sent.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await refresh(devices: true);
      }
    }
  }

  Future<void> power(String action, {int? delay}) async {
    final target = selected;
    if (target == null) return;
    final seconds =
        delay ?? (['Shutdown', 'Restart'].contains(action) ? 10 : 3);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action ${target.name}?'),
        content: Text(
          'Runs after $seconds seconds. You can cancel before it starts. Unsaved work may block shutdown.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep PC on'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (accepted == true && identical(target, selected)) {
      await command('/power', 'POST', {
        'action': action,
        'delaySeconds': seconds,
        'confirmed': true,
      });
    }
  }

  Future<void> addPc() async {
    final result = await Navigator.push<PcProfile>(
      context,
      MaterialPageRoute(builder: (_) => const PairPage()),
    );
    if (!mounted || result == null) return;
    final saved = [...profiles.where((p) => p.pin != result.pin), result];
    try {
      await store.save(saved);
      if (!mounted) return;
      setState(() => profiles = saved);
      pairingRequired.remove(result.pin);
      select(result);
      startDiscovery();
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Could not save pairing securely. Revoke the new entry on the PC and try again.',
        );
      }
    }
  }

  Future<void> forget() async {
    final target = selected;
    if (target == null || busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${target.name}?'),
        content: const Text(
          'This removes the phone’s saved connection. Revoke this phone on the PC to invalidate its credential.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final saved = profiles.where((p) => !identical(p, target)).toList();
    try {
      await store.save(saved);
      if (!mounted) return;
      epoch++;
      api?.close();
      api = null;
      setState(() {
        profiles = saved;
        selected = null;
        status = null;
        message = 'Connection forgotten';
      });
      final preferred = await store.lastSelected();
      if (!mounted) return;
      if (saved.isNotEmpty) {
        select(
          saved.where((p) => normalizePin(p.pin) == preferred).firstOrNull ??
              saved.first,
        );
        startDiscovery();
        unawaited(probeSaved());
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Could not update protected storage.');
      }
    }
  }

  void startDiscovery() {
    if (!foreground || discoverySubscription != null || profiles.isEmpty) {
      return;
    }
    discoverySubscription = PcDiscovery().events.listen(
      (event) {
        if (!mounted) return;
        if (event['kind'] == 'error') {
          setState(
            () => discoveryMessage =
                'Discovery is unavailable. Trying saved addresses; check local network permission and Wi-Fi.',
          );
          return;
        }
        if (event['kind'] == 'started') {
          setState(
            () => discoveryMessage =
                'Automatically looking for saved PCs nearby.',
          );
          return;
        }
        for (final profile in profiles) {
          final address = discoveredAddress(profile, event);
          if (address == null) continue;
          final key = normalizePin(profile.pin);
          final known = candidates.putIfAbsent(key, () => []);
          if (!known.contains(address)) {
            known.insert(0, address);
            if (known.length > 4) known.removeLast();
          }
        }
        if (status == null) refresh(devices: true);
        unawaited(probeSaved());
      },
      onError: (Object _) {
        if (mounted) {
          setState(
            () => discoveryMessage =
                'Discovery unavailable. Saved addresses are still tried automatically.',
          );
        }
      },
    );
  }

  void stopDiscovery() {
    final previous = discoverySubscription;
    discoverySubscription = null;
    unawaited(previous?.cancel() ?? Future<void>.value());
  }

  Future<void> probeSaved() async {
    if (probing || busy || !foreground) return;
    probing = true;
    try {
      for (final profile in List<PcProfile>.of(profiles)) {
        if (!mounted || !foreground) break;
        if (normalizePin(profile.pin) == normalizePin(selected?.pin ?? '') ||
            pairingRequired.contains(profile.pin)) {
          continue;
        }
        final key = normalizePin(profile.pin);
        if (DateTime.now()
                .difference(verifiedAt[key] ?? DateTime(2000))
                .inSeconds <
            10) {
          continue;
        }
        VerifiedPcConnection? connection;
        try {
          connection = await reconnectPc(profile, [
            profile.address,
            ...?candidates[key],
          ]);
          if (mounted) setState(() => verifiedAt[key] = DateTime.now());
        } catch (error) {
          if (error is PcApiException && error.statusCode == 401 && mounted) {
            setState(() => pairingRequired.add(profile.pin));
          }
        } finally {
          connection?.api.close();
        }
      }
    } finally {
      probing = false;
    }
  }

  String profileStatus(PcProfile profile) {
    if (pairingRequired.contains(profile.pin)) return 'Pairing required';
    if (identical(profile, selected) && status != null) return 'Connected';
    final seen = verifiedAt[normalizePin(profile.pin)];
    return seen != null && DateTime.now().difference(seen).inSeconds < 20
        ? 'Available'
        : 'Offline / searching';
  }

  void explainConnections() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('How connections work'),
      content: const SingleChildScrollView(
        child: Text(
          'Pair once: open TapMyPC on your PC and scan its temporary QR. The QR hides after pairing.\n\n'
          'Normal use: open both apps. This phone looks for your saved PCs, verifies their certificates, and reconnects without another code. Each PC has its own pairing.\n\n'
          'Stop connections on the PC pauses access and stays stopped after restart. Start connections to resume.\n\n'
          'Use the PC selector to switch. Commands always target the named PC. Discovery never grants access.\n\n'
          'Both devices need a reachable local network. Public Wi-Fi may block direct connections. Bluetooth transport and internet remote access are not included yet.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  Widget section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    ),
  );
  Widget action(String label, VoidCallback run, {bool supported = true}) =>
      OutlinedButton(
        onPressed: !busy && status != null && supported ? run : null,
        child: Text(label),
      );
  @override
  Widget build(BuildContext context) {
    final audio = status?['audio'];
    final caps = status?['capabilities'] ?? {};
    final pending = status?['scheduler']?['pending'];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TapMyPC.'),
            if (appVersion.isNotEmpty)
              Text(appVersion, style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: explainConnections,
            icon: const Icon(Icons.help_outline),
            tooltip: "How connections work",
          ),
          IconButton(
            onPressed: busy ? null : addPc,
            icon: const Icon(Icons.add),
            tooltip: 'Add PC',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => refresh(devices: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'YOUR PC, A TAP AWAY',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (profiles.isNotEmpty)
              DropdownButton<PcProfile>(
                isExpanded: true,
                value: selected,
                hint: const Text('Select PC'),
                items: profiles
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} · ${profileStatus(p)}'),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (p) {
                        if (p != null) select(p);
                      },
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(message, key: const Key('connection-status')),
            ),
            if (status?['serverVersion'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'PC v${status!['serverVersion']}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            Text(
              discoveryMessage,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (profiles.isEmpty)
              section('Your PCs, together.', [
                const Text(
                  'Pair once with each PC. Your connections are saved securely on this phone.',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: addPc,
                  child: const Text('Add your PC'),
                ),
              ]),
            if (selected != null) ...[
              if (pending != null)
                section('Upcoming on ${selected!.name}', [
                  Text(
                    '${pending['action']} · ${DateTime.parse(pending['dueAt']).toLocal()}',
                  ),
                  action(
                    'Cancel action',
                    () => command('/power/${pending['id']}', 'DELETE', null),
                  ),
                ]),
              section('Sound', [
                Text(
                  audio == null ? 'Unavailable' : '${audio['volume']}%',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                Slider(
                  value: ((audio?['volume'] ?? 0) as num).toDouble().clamp(
                    0,
                    100,
                  ),
                  min: 0,
                  max: 100,
                  onChanged: busy || audio == null
                      ? null
                      : (v) => setState(
                          () => status!['audio']['volume'] = v.round(),
                        ),
                  onChangeEnd: (v) =>
                      command('/audio/volume', 'PUT', {'volume': v.round()}),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    action(
                      '− Volume',
                      () =>
                          command('/audio/step', 'POST', {'direction': 'Down'}),
                      supported: caps['audio'] == true,
                    ),
                    action(
                      audio?['muted'] == true ? 'Unmute' : 'Mute',
                      () => command('/audio/mute', 'PUT', {
                        'muted': audio?['muted'] != true,
                      }),
                      supported: caps['audio'] == true,
                    ),
                    action(
                      '+ Volume',
                      () => command('/audio/step', 'POST', {'direction': 'Up'}),
                      supported: caps['audio'] == true,
                    ),
                  ],
                ),
                for (final output in outputs)
                  action(
                    '${output['isDefault'] == true ? '✓ ' : ''}${output['name']}',
                    () => command('/audio/output', 'PUT', {'id': output['id']}),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in {
                      'Previous': 'Previous',
                      'PlayPause': 'Play / pause',
                      'Next': 'Next',
                    }.entries)
                      action(
                        item.value,
                        () => command('/media', 'POST', {'action': item.key}),
                        supported: caps['media'] == true,
                      ),
                  ],
                ),
              ]),
              section('Power & timers', [
                Wrap(
                  spacing: 8,
                  children: [
                    action(
                      'Monitors off',
                      () => command('/display/off', 'POST', {}),
                      supported: caps['display'] == true,
                    ),
                    for (final item in [
                      'Lock',
                      'Sleep',
                      'Hibernate',
                      'Shutdown',
                      'Restart',
                    ])
                      action(
                        item,
                        () => power(item),
                        supported: item == 'Sleep'
                            ? caps['sleep'] == true
                            : item == 'Hibernate'
                            ? caps['hibernate'] == true
                            : true,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Schedule after 30 minutes'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in ['Sleep', 'Hibernate', 'Shutdown'])
                      action(
                        '$item · 30m',
                        () => power(item, delay: 1800),
                        supported: item == 'Sleep'
                            ? caps['sleep'] == true
                            : item == 'Hibernate'
                            ? caps['hibernate'] == true
                            : true,
                      ),
                  ],
                ),
              ]),
              section('Bluetooth', [
                Text(status?['bluetooth']?['state'] ?? 'Unavailable'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final enabled in [true, false])
                      action(
                        enabled ? 'Turn on' : 'Turn off',
                        () async {
                          if (!enabled) {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Turn off Bluetooth?'),
                                content: const Text(
                                  'Bluetooth headphones, mice, and keyboards will disconnect.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('Turn off'),
                                  ),
                                ],
                              ),
                            );
                            if (ok != true) return;
                          }
                          await command('/bluetooth', 'PUT', {
                            'enabled': enabled,
                          });
                        },
                        supported: status?['bluetooth']?['canControl'] == true,
                      ),
                  ],
                ),
              ]),
              for (final monitor in monitors)
                section(monitor['name'], [
                  Text(
                    monitor['brightness'] == null
                        ? 'Brightness unavailable'
                        : 'Brightness ${monitor['brightness']}%',
                  ),
                  Slider(
                    value: ((monitor['brightness'] ?? 50) as num)
                        .toDouble()
                        .clamp(0, 100),
                    min: 0,
                    max: 100,
                    onChanged:
                        busy ||
                            status == null ||
                            monitor['canSetBrightness'] != true
                        ? null
                        : (v) =>
                              setState(() => monitor['brightness'] = v.round()),
                    onChangeEnd: (v) => command('/monitors/brightness', 'PUT', {
                      'id': monitor['id'],
                      'brightness': v.round(),
                    }),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final enabled in [true, false])
                        action(
                          enabled ? 'Turn on' : 'Turn off',
                          () => command('/monitors/power', 'PUT', {
                            'id': monitor['id'],
                            'enabled': enabled,
                          }),
                          supported: monitor['canSetPower'] == true,
                        ),
                    ],
                  ),
                  if (monitor['message'] != null) Text(monitor['message']),
                ]),
              section('Shortcuts', [
                if (shortcuts.isEmpty)
                  const Text(
                    'Approve apps and websites in the PC app, then refresh here.',
                  ),
                for (final shortcut in shortcuts)
                  action(
                    shortcut['name'],
                    () => command(
                      '/shortcuts/${shortcut['id']}/launch',
                      'POST',
                      {},
                    ),
                  ),
              ]),
              TextButton(
                onPressed: busy ? null : () => refresh(devices: true),
                child: const Text('Refresh devices'),
              ),
              TextButton(
                onPressed: busy ? null : forget,
                child: const Text('Forget selected PC'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    epoch++;
    stopDiscovery();
    timer?.cancel();
    api?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
