import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../connection.dart';

enum RemoteDesktopQuality {
  saveData('save-data', 'Save data'),
  balanced('balanced', 'Balanced'),
  sharper('sharper', 'Sharper');

  const RemoteDesktopQuality(this.id, this.label);
  final String id, label;
}

class RemoteDesktopPreferences {
  RemoteDesktopPreferences([this.storage = const FlutterSecureStorage()]);

  static const _qualityKey = 'tapmypc.remoteDesktop.quality.v1';
  final FlutterSecureStorage storage;
  Future<void> _writes = Future.value();

  Future<RemoteDesktopQuality> loadQuality() async {
    await _writes.catchError((Object _) {});
    final saved = await storage.read(key: _qualityKey);
    return RemoteDesktopQuality.values
            .where((q) => q.id == saved)
            .firstOrNull ??
        RemoteDesktopQuality.balanced;
  }

  Future<void> saveQuality(RemoteDesktopQuality value) => _writes = _writes
      .catchError((Object _) {})
      .then((_) => storage.write(key: _qualityKey, value: value.id));
}

enum _ScreenFit {
  fit('Fit'),
  fill('Fill');

  const _ScreenFit(this.label);
  final String label;
}

class RemoteDesktopPage extends StatefulWidget {
  const RemoteDesktopPage({
    super.key,
    required this.profile,
    required this.revision,
    required this.preferences,
    required this.savePassword,
  });

  final PcProfile profile;
  final ValueListenable<int?> revision;
  final RemoteDesktopPreferences preferences;
  final Future<void> Function(String?) savePassword;

  @override
  State<RemoteDesktopPage> createState() => _RemoteDesktopPageState();
}

class _RemoteDesktopPageState extends State<RemoteDesktopPage>
    with WidgetsBindingObserver {
  late final PcApi _api = PcApi(widget.profile);
  MethodChannel? _bridge;
  WebSocket? _socket;
  Timer? _viewerStartup;
  final _password = TextEditingController();
  late bool _hasSavedPassword = widget.profile.desktopPassword != null;
  bool _passwordRequired = false;
  bool _showPassword = false;
  bool _rememberPassword = false;
  bool _savingPassword = false;
  String? _pendingPassword;
  bool _started = false;
  bool _ended = false;
  bool _connected = false;
  bool _passwordSubmitted = false;
  String? _error;
  RemoteDesktopQuality _quality = RemoteDesktopQuality.balanced;
  _ScreenFit _screenFit = _ScreenFit.fit;
  final _resolution = ValueNotifier<String?>(null);
  bool _orientationOverridden = false;

  String get _disconnectMessage => _passwordSubmitted && !_connected
      ? 'UltraVNC closed the connection while checking the VNC password. Check the password and restart UltraVNC after changing it.'
      : 'The desktop session ended.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.revision.addListener(_desktopChanged);
    _viewerStartup = Timer(const Duration(seconds: 10), () {
      _end(
        'The desktop viewer could not start. Update Android System WebView and try again.',
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _end('Remote Desktop ended when TapMyPC left the foreground.');
    }
  }

  Future<void> _attach(int id) async {
    if (_ended) return;
    final bridge = MethodChannel('dev.tapmypc/remote-desktop/$id');
    _bridge = bridge;
    bridge.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'ready':
          _viewerStartup?.cancel();
          unawaited(_open(bridge));
        case 'input':
          final bytes = call.arguments;
          if (!_ended && bytes is Uint8List) _socket?.add(bytes);
        case 'passwordRequired':
          if (_ended || _passwordRequired || _passwordSubmitted) return;
          final saved = _hasSavedPassword
              ? widget.profile.desktopPassword
              : null;
          if (saved != null) {
            unawaited(_submitPassword(saved));
          } else {
            setState(() => _passwordRequired = true);
          }
        case 'connected':
          if (mounted && !_ended) {
            setState(() => _connected = true);
            final socket = _socket;
            if (socket != null &&
                socket.readyState == WebSocket.open &&
                socket.protocol == PcApi.remoteDesktopViewerStatusProtocol) {
              socket.add('viewer-ready');
            }
            final password = _pendingPassword;
            _pendingPassword = null;
            if (password != null) unawaited(_savePassword(password));
          }
        case 'resolution':
          final resolution = call.arguments;
          if (!_ended && resolution is String) _resolution.value = resolution;
        case 'authenticationFailed':
          _end(
            'UltraVNC rejected the connection. Check its service and password on the PC.',
          );
        case 'disconnected':
          _end(_disconnectMessage);
      }
    });
    try {
      await bridge.invokeMethod<void>('start');
    } on PlatformException catch (error) {
      _end(error.message ?? 'The desktop viewer could not start.');
    }
  }

  Future<void> _submitPassword(String value) async {
    if (_ended || _passwordSubmitted || value.isEmpty) return;
    setState(() {
      _passwordSubmitted = true;
      _passwordRequired = false;
      _pendingPassword = _rememberPassword ? value : null;
    });
    _password.clear();
    try {
      await _bridge?.invokeMethod<void>('password', value);
    } on PlatformException {
      _end('The viewer could not send the VNC password.');
    }
  }

  Future<void> _savePassword(String? value) async {
    if (_savingPassword) return;
    setState(() => _savingPassword = true);
    try {
      await widget.savePassword(value);
      if (mounted) {
        setState(() => _hasSavedPassword = value != null);
        if (value == null) {
          final messenger = ScaffoldMessenger.of(context);
          if (_error != null) Navigator.pop(context);
          messenger.showSnackBar(
            const SnackBar(content: Text('Saved VNC password removed.')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update the saved VNC password.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _desktopChanged() {
    if (!_connected || _ended || widget.revision.value == null) return;
    unawaited(_sendViewerCommand('desktopChanged'));
  }

  Future<void> _sendViewerCommand(String method, [String? value]) async {
    if (!_connected || _ended) return;
    try {
      await _bridge?.invokeMethod<void>(method, value);
    } on PlatformException {
      if (mounted && !_ended) {
        _showMessage('The viewer could not apply this action.');
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeQuality(RemoteDesktopQuality quality) async {
    _quality = quality;
    unawaited(_sendViewerCommand('quality', quality.id));
    try {
      await widget.preferences.saveQuality(quality);
    } catch (_) {
      if (mounted && _quality == quality) {
        _showMessage('Quality could not be saved.');
      }
    }
  }

  Future<void> _rotate() async {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    _orientationOverridden = true;
    try {
      await SystemChrome.setPreferredOrientations(
        portrait
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [DeviceOrientation.portraitUp],
      );
    } on PlatformException {
      if (mounted) _showMessage('This device could not rotate the viewer.');
    }
  }

  Future<void> _open(MethodChannel bridge) async {
    if (_started || _ended) return;
    _started = true;
    try {
      try {
        _quality = await widget.preferences.loadQuality();
      } catch (_) {
        if (mounted && !_ended) {
          _showMessage('Saved quality could not be loaded.');
        }
      }
      if (_ended) return;
      final socket = await _api.openRemoteDesktop();
      if (_ended) {
        unawaited(socket.close());
        return;
      }
      _socket = socket;
      await bridge.invokeMethod<void>('open', _quality.id);
      await for (final packet in socket) {
        if (_ended) break;
        if (packet is! List<int>) {
          _end('The PC sent an unexpected desktop message.');
          break;
        }
        await bridge.invokeMethod<void>(
          'screen',
          packet is Uint8List ? packet : Uint8List.fromList(packet),
        );
      }
      _end(_disconnectMessage);
    } on WebSocketException catch (error) {
      _end(switch (error.httpStatusCode) {
        401 => 'Pair this phone with the PC again.',
        403 => 'Enable Remote Desktop for this phone in TapMyPC on the PC.',
        409 => 'Another Remote Desktop session is already open.',
        503 =>
          'On the PC, open Configure → Remote Desktop and select Set up Remote Desktop.',
        _ =>
          'Could not open Remote Desktop. Check the PC connection and try again.',
      });
    } on Object {
      _end(
        _socket == null
            ? 'Could not open Remote Desktop. Check the PC connection and try again.'
            : _disconnectMessage,
      );
    }
  }

  void _stop() {
    if (_ended) return;
    _ended = true;
    _viewerStartup?.cancel();
    _pendingPassword = null;
    _bridge?.setMethodCallHandler(null);
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close(WebSocketStatus.normalClosure));
    if (_started) _api.close();
  }

  void _end(String error) {
    if (_ended) return;
    _stop();
    if (mounted) setState(() => _error = error);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.revision.removeListener(_desktopChanged);
    _stop();
    if (_orientationOverridden) {
      unawaited(SystemChrome.setPreferredOrientations([]));
    }
    _resolution.dispose();
    _password.dispose();
    super.dispose();
  }

  Widget _passwordPanel() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _password,
                  decoration: InputDecoration(
                    labelText: 'UltraVNC password',
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() => _showPassword = !_showPassword);
                      },
                    ),
                  ),
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: _submitPassword,
                ),
                CheckboxListTile(
                  value: _rememberPassword,
                  onChanged: (value) =>
                      setState(() => _rememberPassword = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remember for this PC'),
                ),
                FilledButton(
                  onPressed: () => _submitPassword(_password.text),
                  child: const Text('Connect'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _showOptions() async {
    final forgetPassword = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (context) => StatefulBuilder(
        builder: (context, updateSheet) {
          final text = Theme.of(context).textTheme;
          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remote Desktop options', style: text.titleLarge),
                  if (_connected && !_ended) ...[
                    const SizedBox(height: 16),
                    Text('Screen scaling', style: text.titleMedium),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<_ScreenFit>(
                        segments: [
                          for (final fit in _ScreenFit.values)
                            ButtonSegment(value: fit, label: Text(fit.label)),
                        ],
                        selected: {_screenFit},
                        onSelectionChanged: (value) {
                          updateSheet(() => _screenFit = value.single);
                          unawaited(
                            _sendViewerCommand('scale', _screenFit.name),
                          );
                        },
                      ),
                    ),
                    Text(
                      _screenFit == _ScreenFit.fit
                          ? 'Show the entire desktop at its original aspect ratio.'
                          : 'Fill the viewer at the original aspect ratio. Edges may be cropped.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text('Image quality', style: text.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final quality in RemoteDesktopQuality.values)
                          ChoiceChip(
                            label: Text(quality.label),
                            selected: _quality == quality,
                            onSelected: (selected) {
                              if (!selected) return;
                              unawaited(_changeQuality(quality));
                              updateSheet(() {});
                            },
                          ),
                      ],
                    ),
                    ValueListenableBuilder<String?>(
                      valueListenable: _resolution,
                      builder: (_, resolution, _) => Text(
                        resolution == null
                            ? 'Audio unavailable'
                            : 'Capture resolution: $resolution · Audio unavailable',
                        style: text.bodySmall,
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.refresh),
                      title: const Text('Refresh screen'),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_sendViewerCommand('refresh'));
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.keyboard_command_key),
                      title: const Text('Send Ctrl+Alt+Del'),
                      onTap: () {
                        Navigator.pop(context);
                        unawaited(_sendViewerCommand('secureAttention'));
                      },
                    ),
                  ],
                  if (_hasSavedPassword)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.key_off_outlined),
                      title: const Text('Forget saved VNC password'),
                      onTap: _savingPassword
                          ? null
                          : () => Navigator.pop(context, true),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (forgetPassword == true && mounted) await _savePassword(null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 4,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          tooltip: 'Disconnect',
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(widget.profile.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (_connected && !_ended) ...[
            IconButton(
              onPressed: () => _sendViewerCommand('keyboard'),
              tooltip: 'Show keyboard',
              icon: const Icon(Icons.keyboard_outlined),
            ),
            IconButton(
              onPressed: _rotate,
              tooltip: 'Rotate screen',
              icon: const Icon(Icons.screen_rotation_outlined),
            ),
          ],
          if ((_connected && !_ended) || _hasSavedPassword)
            IconButton(
              onPressed: _showOptions,
              tooltip: 'Remote Desktop options',
              icon: const Icon(Icons.more_vert),
            ),
        ],
        bottom: _error == null && !_connected
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: SafeArea(
        child: _error == null && Platform.isAndroid
            ? Stack(
                fit: StackFit.expand,
                children: [
                  AndroidView(
                    viewType: 'dev.tapmypc/remote-desktop-view',
                    onPlatformViewCreated: _attach,
                  ),
                  if (_passwordRequired)
                    const ColoredBox(color: Colors.black54),
                  if (_passwordRequired) _passwordPanel(),
                ],
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error ?? 'Remote Desktop is available on Android.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
      ),
    );
  }
}
