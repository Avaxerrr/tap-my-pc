import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'connection.dart';
import 'pairing_page.dart';
import 'discovery.dart';
import 'ui/app_theme.dart';
import 'ui/remote_dashboard.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TapMyPcApp());
}

class TapMyPcApp extends StatefulWidget {
  const TapMyPcApp({super.key});
  @override
  State<TapMyPcApp> createState() => _TapMyPcAppState();
}

class _TapMyPcAppState extends State<TapMyPcApp> with WidgetsBindingObserver {
  final appearance = AppearanceController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(appearance.load());
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appearance,
    builder: (context, _) => AppearanceScope(
      controller: appearance,
      child: MaterialApp(
        title: 'TapMyPC',
        debugShowCheckedModeBanner: false,
        theme: appTheme(appearance.palette),
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 180),
        home: const RemotePage(),
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appearance.dispose();
    super.dispose();
  }
}

class RemotePage extends StatefulWidget {
  final PcApi Function(PcProfile) createApi;
  const RemotePage({super.key, this.createApi = PcApi.new});
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
  String? feedback, lastServerTime;
  bool feedbackError = false;
  Map<String, dynamic>? pendingSnapshot;
  Map<String, String> deviceErrors = {};
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
      ticks++;
      refresh(devices: deviceErrors.isNotEmpty && ticks % 5 == 0);
      if (ticks % 5 == 0) probeSaved();
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
    api = widget.createApi(profile);
    setState(() {
      selected = profile;
      status = null;
      pendingSnapshot = null;
      lastServerTime = null;
      feedback = null;
      feedbackError = false;
      deviceErrors = {};
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
      final loadDevices = devices || status == null;
      // A verified status response establishes connectivity. Optional device
      // lists must not turn a reachable PC into an offline one.
      setState(() {
        status = next;
        final pending = next['scheduler']?['pending'];
        pendingSnapshot = pending == null
            ? null
            : Map<String, dynamic>.from(pending);
        lastServerTime = next['serverTime'];
        verifiedAt[normalizePin(selected!.pin)] = DateTime.now();
        message = 'Connected to ${selected!.name}';
      });
      if (loadDevices) {
        final errors = <String, String>{};
        Future<List<dynamic>> loadList(String path, String label) async {
          try {
            return await activeClient.request(path) as List<dynamic>;
          } catch (error) {
            // Revoked credentials still invalidate the entire connection.
            if (error is PcApiException && error.statusCode == 401) rethrow;
            final detail = error is PcApiException
                ? ' (HTTP ${error.statusCode})'
                : '';
            errors[path] =
                '$label could not be loaded$detail. Pull to refresh.';
            return [];
          }
        }

        final lists = await Future.wait([
          loadList('/audio/outputs', 'Audio outputs'),
          loadList('/monitors', 'Individual display controls'),
          loadList('/shortcuts', 'Shortcuts'),
        ]);
        if (!mounted || generation != epoch) return;
        setState(() {
          outputs = lists[0];
          monitors = lists[1];
          shortcuts = lists[2];
          deviceErrors = errors;
        });
      }
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

  String friendly(Object error) => error is HttpException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');
  Future<void> command(String path, String method, Object? body) async {
    if (busy || status == null || api == null) return;
    final generation = epoch;
    final client = api!;
    setState(() {
      busy = true;
      feedback = null;
      feedbackError = false;
    });
    try {
      final result = await client.request(path, method: method, body: body);
      if (!mounted || generation != epoch) return;
      setState(() {
        feedback =
            result['feedback']?['message'] ??
            (method == 'DELETE' ? 'Timer canceled.' : 'Action scheduled.');
        if (method == 'DELETE') pendingSnapshot = null;
      });
    } catch (error) {
      if (mounted && generation == epoch) {
        setState(() {
          feedbackError = true;
          feedback = '${friendly(error)} No automatic retry was sent.';
        });
      }
    } finally {
      if (mounted && generation == epoch) {
        setState(() => busy = false);
        await refresh(devices: true);
      }
    }
  }

  Future<void> setBluetooth(bool enabled) async {
    if (busy || selected == null || status == null) return;
    final generation = epoch;
    if (!enabled) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Turn off Bluetooth on ${selected!.name}?'),
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
    if (!mounted || generation != epoch) return;
    await command('/bluetooth', 'PUT', {'enabled': enabled});
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

  @override
  Widget build(BuildContext context) => RemoteDashboard(
    profiles: profiles,
    selected: selected,
    status: status,
    message: message,
    appVersion: appVersion,
    discoveryMessage: discoveryMessage,
    busy: busy,
    feedback: feedback,
    feedbackError: feedbackError,
    pending: pendingSnapshot,
    serverTime: lastServerTime,
    deviceErrors: deviceErrors,
    outputs: outputs,
    monitors: monitors,
    shortcuts: shortcuts,
    profileStatus: profileStatus,
    onSelect: select,
    onAdd: addPc,
    onForget: forget,
    onRefresh: () => refresh(devices: true),
    onHelp: explainConnections,
    send: command,
    power: power,
    onBluetooth: setBluetooth,
    onVolumePreview: (value) =>
        setState(() => status!['audio']['volume'] = value.round()),
    onBrightnessPreview: (id, value) => setState(
      () => monitors.firstWhere((m) => m['id'] == id)['brightness'] = value
          .round(),
    ),
  );

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
