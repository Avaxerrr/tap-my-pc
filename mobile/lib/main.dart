import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'connection.dart';
import 'phone_identity.dart';
import 'bluetooth_connection.dart';
import 'selected_connection.dart';
import 'pairing_page.dart';
import 'discovery.dart';
import 'ui/app_theme.dart';
import 'ui/remote_dashboard.dart';
import 'ui/network_address_editor.dart';
import 'ui/wake_on_lan_editor.dart';
import 'wake_on_lan.dart';

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
  bool editingConnection = false;
  bool awaitingWake = false;
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
  final Set<String> unsavedProfiles = {};
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
      PhoneIdentity.refresh();
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
    api = null;
    setState(() {
      selected = profile;
      status = null;
      pendingSnapshot = null;
      lastServerTime = null;
      awaitingWake = false;
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
    if (selected == null ||
        editingConnection ||
        busy ||
        refreshing ||
        !foreground ||
        pairingRequired.contains(selected?.pin)) {
      return;
    }
    refreshing = true;
    try {
      Map<String, dynamic> next;
      final current = selected!;
      final hints = candidates[normalizePin(current.pin)] ?? [];
      final preferNetwork =
          current.connectionMode == 'auto' &&
          ticks % 5 == 0 &&
          client != null &&
          client.transportLabel != 'Local network';
      VerifiedPcConnection? recovered;
      if (client == null || preferNetwork) {
        recovered = await connectSelectedPc(
          current,
          hints,
          wifi: widget.createApi,
          activeApi: client,
        );
        next = recovered.status;
      } else {
        try {
          next = Map<String, dynamic>.from(await client.request('/status'));
        } catch (error) {
          if (!mounted || generation != epoch) return;
          if (error is PcApiException && error.statusCode == 401) rethrow;
          setState(() {
            status = null;
            message = 'Reconnecting to ${current.name}…';
          });
          recovered = await connectSelectedPc(
            current,
            hints,
            wifi: widget.createApi,
            excludedAddresses: client.isBluetooth
                ? {}
                : {client.profile.address},
          );
          next = recovered.status;
        }
      }
      if (recovered != null) {
        if (!mounted || generation != epoch || busy) {
          if (!identical(recovered.api, api)) recovered.api.close();
          return;
        }
        if (!identical(api, recovered.api)) api?.close();
        api = recovered.api;
        await rememberVerifiedProfile(recovered.profile, generation);
      }
      if (!mounted || generation != epoch) return;
      final activeClient = api!;
      var verified = selected!
          .copy(keyPin: activeClient.verifiedProfile.keyPin)
          .withNetworkHints(next['networkConnection']);
      final bluetoothInfo = next['bluetoothConnection'];
      if (bluetoothInfo is Map &&
          bluetoothInfo['address'] is String &&
          bluetoothInfo['serviceId'] ==
              '8cf69287-4d5e-47f1-97c8-0a4ec3b5d290' &&
          RegExp(
            r'^(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$',
          ).hasMatch(bluetoothInfo['address'])) {
        verified = verified.withBluetoothAddress(
          (bluetoothInfo['address'] as String).toUpperCase(),
        );
      }
      await rememberVerifiedProfile(
        verified,
        generation,
        network: next['networkConnection'],
      );
      if (!mounted || generation != epoch) return;
      final loadDevices = devices || status == null;
      // A verified status response establishes connectivity. Optional device
      // lists must not turn a reachable PC into an offline one.
      setState(() {
        status = next;
        if (awaitingWake) {
          awaitingWake = false;
          feedback = '${selected!.name} is back online.';
          feedbackError = false;
        }
        final pending = next['scheduler']?['pending'];
        pendingSnapshot = pending == null
            ? null
            : Map<String, dynamic>.from(pending);
        lastServerTime = next['serverTime'];
        verifiedAt[normalizePin(selected!.pin)] = DateTime.now();
        message =
            'Connected to ${selected!.name} · ${activeClient.transportLabel}${unsavedProfiles.contains(selected!.pin) ? '. Identity storage failed; retrying automatically.' : ''}';
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

  String friendly(Object error) => switch (error) {
    HttpException e => e.message,
    HandshakeException e => e.message,
    FormatException e => e.message,
    PlatformException e => e.message ?? 'Bluetooth is unavailable.',
    _ => error.toString().replaceFirst('Exception: ', ''),
  };
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
    if (api?.isBluetooth == true) {
      setState(
        () => message =
            'Switch to local network or Tailscale to change the PC’s Bluetooth.',
      );
      return;
    }
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
    if (api?.isBluetooth == true) return;
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

  Future<void> rememberVerifiedProfile(
    PcProfile updated,
    int generation, {
    Object? network,
  }) async {
    if (!mounted || generation != epoch || editingConnection) return;
    final original = profiles.where((p) => p.pin == updated.pin).firstOrNull;
    if (original == null || original.token != updated.token) return;
    final automatic = original
        .withAutomaticWakeHint(network)
        .automaticWakeOnLan;
    if ((original.keyPin == updated.keyPin &&
        original.address == updated.address &&
        original.localEndpoint == updated.localEndpoint &&
        original.tailscaleEndpoint == updated.tailscaleEndpoint &&
        original.bluetoothAddress == updated.bluetoothAddress &&
        original.connectionMode == updated.connectionMode &&
        original.automaticWakeOnLan == automatic &&
        !unsavedProfiles.contains(updated.pin))) {
      return;
    }
    updated = updated
        .withWakeOnLan(original.wakeOnLan)
        .copy(automaticWakeOnLan: automatic);
    setState(() {
      profiles = profiles
          .map((p) => p.pin == updated.pin ? updated : p)
          .toList();
      if (selected?.pin == updated.pin) selected = updated;
    });
    unsavedProfiles.add(updated.pin);
    try {
      await store.save(profiles);
      unsavedProfiles.remove(updated.pin);
    } catch (_) {
      if (mounted && generation == epoch) {
        setState(
          () => message =
              'Connected, but the renewed identity could not be saved securely. Try connecting again.',
        );
      }
    }
  }

  Future<void> wakeSettings() async {
    final target = selected;
    if (target == null || busy || editingConnection) return;
    editingConnection = true;
    var saving = false;
    try {
      final edited = await showDialog<({WakeOnLanSettings? settings})>(
        context: context,
        builder: (_) => WakeOnLanEditor(profile: target),
      );
      if (!mounted || edited == null || selected?.pin != target.pin) return;
      final updated = selected!.withWakeOnLan(edited.settings);
      final saved = profiles
          .map((p) => p.pin == target.pin ? updated : p)
          .toList();
      saving = true;
      setState(() => busy = true);
      await store.save(saved);
      if (!mounted) return;
      setState(() {
        profiles = saved;
        selected = updated;
        awaitingWake = false;
        feedback = updated.wakeOnLan == null
            ? updated.automaticWakeOnLan == null
                  ? 'Wake-on-LAN settings removed.'
                  : 'Using automatic wake settings for ${target.name}.'
            : 'Wake-on-LAN settings saved for ${target.name}.';
        feedbackError = false;
      });
    } catch (_) {
      if (mounted && selected?.pin == target.pin) {
        setState(() {
          feedback = 'Could not save Wake-on-LAN settings.';
          feedbackError = true;
        });
      }
    } finally {
      editingConnection = false;
      if (mounted) {
        if (saving) setState(() => busy = false);
        unawaited(refresh());
      }
    }
  }

  Future<void> wakeSelected() async {
    final target = selected;
    final settings = target?.effectiveWakeOnLan;
    if (target == null ||
        settings == null ||
        status != null ||
        busy ||
        editingConnection ||
        !foreground ||
        pairingRequired.contains(target.pin)) {
      return;
    }
    final generation = epoch;
    setState(() {
      busy = true;
      awaitingWake = false;
    });
    try {
      await settings.send();
      if (!mounted || generation != epoch) return;
      setState(() {
        awaitingWake = status == null;
        feedback = awaitingWake
            ? 'Wake packet sent to ${target.name}. Checking for reconnection…'
            : '${target.name} is online.';
        feedbackError = false;
      });
    } catch (error) {
      if (!mounted || generation != epoch) return;
      setState(() {
        feedback = error is PlatformException
            ? error.message ?? 'Could not send the wake packet.'
            : 'Could not send the wake packet.';
        feedbackError = true;
      });
    } finally {
      if (mounted && generation == epoch) {
        setState(() => busy = false);
        unawaited(refresh());
      }
    }
  }

  Future<void> connectionSettings() async {
    final target = selected;
    if (target == null || busy) return;
    if (editingConnection) return;
    editingConnection = true;
    epoch++;
    try {
      final mode = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('Connection for ${target.name}'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Current: ${status == null ? 'Disconnected' : api?.transportLabel ?? 'Disconnected'}',
                  ),
                  const SizedBox(height: 12),
                  for (final choice in const [
                    (
                      'auto',
                      'Automatic',
                      'Local network → Tailscale → Bluetooth. No commands are resent.',
                    ),
                    (
                      'local',
                      'Local network only',
                      'Stay on your home or office network.',
                    ),
                    (
                      'tailscale',
                      'Tailscale only',
                      'Stay on Tailscale; no local or Bluetooth fallback.',
                    ),
                    (
                      'bluetooth',
                      'Bluetooth only',
                      'Use Bluetooth without the local network.',
                    ),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(choice.$2),
                      subtitle: Text(choice.$3),
                      trailing: target.connectionMode == choice.$1
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(dialog, choice.$1),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Local network address'),
                    subtitle: Text(
                      target.localEndpoint == null
                          ? 'Discovered automatically when nearby'
                          : endpointHost(target.localEndpoint!),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => Navigator.pop(dialog, 'local-address'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tailscale address'),
                    subtitle: Text(
                      target.tailscaleEndpoint == null
                          ? 'Set up remote access'
                          : endpointHost(target.tailscaleEndpoint!),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => Navigator.pop(dialog, 'tailscale-address'),
                  ),
                  if (target.bluetoothAddress == null)
                    const Text(
                      'Connect over a network once to save this PC’s Bluetooth connection.',
                    ),
                  TextButton(
                    onPressed: () async {
                      try {
                        if (await PhoneBluetooth.requestAccess()) {
                          await PhoneBluetooth.openSettings();
                        }
                      } catch (error) {
                        if (mounted) setState(() => message = friendly(error));
                      }
                    },
                    child: const Text('Phone Bluetooth settings'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (!mounted || mode == null || selected?.pin != target.pin || busy) {
        return;
      }
      if (mode == 'local-address' || mode == 'tailscale-address') {
        await changeNetworkAddress(
          target,
          tailscale: mode == 'tailscale-address',
        );
        return;
      }
      if (mode == 'tailscale' && target.tailscaleEndpoint == null) {
        await changeNetworkAddress(
          target,
          tailscale: true,
          modeAfterSave: 'tailscale',
        );
        return;
      }
      if (mode == 'bluetooth' && target.bluetoothAddress == null) {
        setState(
          () => message =
              'Connect to this PC over a network once before selecting Bluetooth.',
        );
        return;
      }
      try {
        if (mode == 'bluetooth' &&
            target.bluetoothAddress != null &&
            !await PhoneBluetooth.requestAccess()) {
          if (mounted) {
            setState(
              () => message =
                  'Nearby devices permission is needed for Bluetooth.',
            );
          }
          return;
        }
        if (!mounted || selected?.pin != target.pin) return;
        final updated = target.withConnectionMode(mode);
        final saved = profiles
            .map((p) => p.pin == target.pin ? updated : p)
            .toList();
        await store.save(saved);
        if (!mounted || selected?.pin != target.pin) return;
        setState(() => profiles = saved);
        select(updated);
      } catch (error) {
        if (mounted) setState(() => message = friendly(error));
      }
    } finally {
      editingConnection = false;
      if (mounted) refresh(devices: true);
    }
  }

  Future<void> changeNetworkAddress(
    PcProfile target, {
    required bool tailscale,
    String? modeAfterSave,
  }) async {
    final endpoint = await showDialog<String>(
      context: context,
      builder: (_) =>
          NetworkAddressEditor(profile: target, tailscale: tailscale),
    );
    if (!mounted || endpoint == null || selected?.pin != target.pin) return;
    final generation = epoch;
    VerifiedPcConnection? verified;
    setState(() {
      busy = true;
      message = 'Verifying ${target.name} at the new address…';
    });
    try {
      // Verify exactly the edited route; no fallback can validate a different address.
      verified = await reconnectPc(target.atAddress(endpoint), [
        endpoint,
      ], createApi: widget.createApi);
      if (!mounted || generation != epoch) return;
      final updated = verified.profile
          .withNetworkHints(verified.status['networkConnection'])
          .withAutomaticWakeHint(verified.status['networkConnection'])
          .withConnectionMode(modeAfterSave ?? target.connectionMode);
      final saved = profiles
          .map((p) => p.pin == target.pin ? updated : p)
          .toList();
      await store.save(saved);
      if (!mounted || generation != epoch) return;
      setState(() => profiles = saved);
      select(updated);
    } catch (error) {
      if (mounted && generation == epoch) {
        setState(() {
          message = 'Address was not saved. ${friendly(error)}';
          feedback = message;
          feedbackError = true;
        });
      }
    } finally {
      verified?.api.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recoverPc() async {
    final target = selected;
    if (target == null || busy) return;
    await enrollPc(recovering: target);
  }

  Future<void> addPc() => enrollPc();

  Future<void> enrollPc({PcProfile? recovering}) async {
    if (editingConnection) return;
    editingConnection = true;
    epoch++;
    try {
      final result = await Navigator.push<PcProfile>(
        context,
        MaterialPageRoute(builder: (_) => PairPage(recovering: recovering)),
      );
      if (!mounted || result == null) return;
      final saved = replacePcProfile(profiles, result, recovering: recovering);
      try {
        await store.save(saved);
        if (!mounted) return;
        setState(() => profiles = saved);
        pairingRequired.remove(result.pin);
        if (recovering != null) pairingRequired.remove(recovering.pin);
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
    } finally {
      editingConnection = false;
      if (mounted) refresh(devices: true);
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
    if (probing || busy || editingConnection || !foreground) return;
    probing = true;
    try {
      for (final profile in List<PcProfile>.of(profiles)) {
        if (!mounted || !foreground || editingConnection) break;
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
        final generation = epoch;
        try {
          connection = await connectSelectedPc(profile, [
            profile.address,
            ...?candidates[key],
          ]);
          if (mounted) {
            await rememberVerifiedProfile(
              connection.profile,
              generation,
              network: connection.status['networkConnection'],
            );
            if (mounted) setState(() => verifiedAt[key] = DateTime.now());
          }
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
          'First pairing needs a reachable network address. In Connection settings, Automatic tries local network, then Tailscale, then Bluetooth. The three Only modes stay on the chosen route. Commands are never resent across connections.\n\nFor remote access, connect Tailscale on both devices and enable Allow access through Tailscale on the PC. Your phone learns the address when it connects. You can also enter just the Tailscale IP; the existing port is reused. Local and Tailscale addresses are saved separately.\n\nBluetooth can work nearby even without the same Wi-Fi. Allow Nearby devices and complete system Bluetooth pairing if prompted. The PC must be awake and running TapMyPC',
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
    onRecover: recoverPc,
    onConnection: connectionSettings,
    onWakeSettings: wakeSettings,
    onWake: pairingRequired.contains(selected?.pin) ? null : wakeSelected,
    onRefresh: () => refresh(devices: true),
    onHelp: explainConnections,
    send: command,
    power: power,
    onBluetooth: setBluetooth,
    usingBluetooth: api?.isBluetooth ?? false,
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
