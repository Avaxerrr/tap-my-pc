import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../connection.dart';
import 'remote_desktop_audio.dart';
import 'remote_desktop_preferences.dart';
import 'remote_desktop_stream_options.dart';

class RemoteDesktopPage extends StatefulWidget {
  const RemoteDesktopPage({
    super.key,
    required this.profile,
    required this.revision,
    required this.audioPermission,
    required this.preferences,
    required this.savePassword,
  });

  final PcProfile profile;
  final ValueListenable<int?> revision;
  final ValueListenable<bool?> audioPermission;
  final RemoteDesktopPreferences preferences;
  final Future<void> Function(String?) savePassword;

  @override
  State<RemoteDesktopPage> createState() => _RemoteDesktopPageState();
}

class _DesktopAttempt {
  _DesktopAttempt(this.profile);

  final PcProfile profile;
  PcApi? api;
  MethodChannel? bridge;
  WebSocket? socket;
  Timer? timeout;
  DateTime? connectedAt;
  bool opening = false;
}

class _RemoteDesktopPageState extends State<RemoteDesktopPage>
    with WidgetsBindingObserver {
  late final _audio = RemoteDesktopAudio(widget.profile);
  _DesktopAttempt? _attempt;
  MethodChannel? get _bridge => _attempt?.bridge;
  Timer? _retryTimer;
  bool _autoRecoveryUsed = false;
  bool _canReconnect = false;
  bool _audioPreferred = false;
  Timer? _audioStartTimer;
  String? _sessionPassword;
  final _password = TextEditingController();
  late bool _hasSavedPassword = widget.profile.desktopPassword != null;
  bool _passwordRequired = false;
  bool _showPassword = false;
  bool _rememberPassword = false;
  bool _savingPassword = false;
  String? _pendingPassword;
  bool _ended = false;
  bool _connected = false;
  bool _passwordSubmitted = false;
  String? _error;
  RemoteDesktopStreamSettings _stream = const RemoteDesktopStreamSettings();
  final _streamStats = ValueNotifier<Map<String, dynamic>>({});
  bool _fullscreen = false;
  bool _toolbarExpanded = false;
  RemoteDesktopScreenFit _screenFit = RemoteDesktopScreenFit.fit;
  final _resolution = ValueNotifier<String?>(null);
  bool _orientationOverridden = false;

  bool _isCurrent(_DesktopAttempt attempt) =>
      mounted && !_ended && identical(_attempt, attempt);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.revision.addListener(_desktopChanged);
    widget.audioPermission.addListener(_audioPermissionChanged);
    _audio.addListener(_audioChanged);
    _beginAttempt();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _end('Remote Desktop ended when TapMyPC left the foreground.');
    }
  }

  void _beginAttempt() {
    final attempt = _DesktopAttempt(widget.profile);
    _attempt = attempt;
    attempt.timeout = Timer(const Duration(seconds: 10), () {
      if (_isCurrent(attempt)) {
        _end(
          'The viewer could not start. Check Android System WebView.',
          reconnect: true,
        );
      }
    });
  }

  void _watchHandshake(_DesktopAttempt attempt) {
    attempt.timeout?.cancel();
    attempt.timeout = Timer(const Duration(seconds: 12), () {
      if (_isCurrent(attempt)) {
        _end('UltraVNC did not finish signing in.', reconnect: true);
      }
    });
  }

  Future<void> _attach(_DesktopAttempt attempt, int id) async {
    if (!_isCurrent(attempt)) return;
    final bridge = MethodChannel('dev.tapmypc/remote-desktop/$id');
    attempt.bridge = bridge;
    _audio.attach(bridge);
    bridge.setMethodCallHandler((call) async {
      if (!_isCurrent(attempt)) return;
      switch (call.method) {
        case 'ready':
          attempt.timeout?.cancel();
          // Dart can report a late TLS read as an uncaught socket event.
          // Attribute it to this attempt, including when it has since closed.
          runZonedGuarded(() => unawaited(_open(attempt, bridge)), (
            error,
            stack,
          ) {
            if (error is SocketException) {
              if (_isCurrent(attempt)) {
                _interrupted(
                  attempt,
                  'The desktop connection was interrupted.',
                );
              }
            } else {
              Zone.current.handleUncaughtError(error, stack);
            }
          });
        case 'input':
          final bytes = call.arguments;
          final socket = attempt.socket;
          if (bytes is Uint8List && socket?.readyState == WebSocket.open) {
            try {
              socket!.add(bytes);
            } on StateError {
              _interrupted(
                attempt,
                'The desktop connection closed while sending input.',
              );
            }
          }
        case 'passwordRequired':
          if (_passwordRequired || _passwordSubmitted) return;
          attempt.timeout?.cancel();
          final saved =
              _sessionPassword ??
              (_hasSavedPassword ? widget.profile.desktopPassword : null);
          if (saved != null) {
            unawaited(_submitPassword(saved, allowSave: false));
          } else {
            setState(() => _passwordRequired = true);
          }
        case 'connected':
          if (!_connected) {
            attempt.timeout?.cancel();
            attempt.connectedAt = DateTime.now();
            setState(() => _connected = true);
            final socket = attempt.socket;
            if (socket != null &&
                socket.readyState == WebSocket.open &&
                socket.protocol == PcApi.remoteDesktopViewerStatusProtocol) {
              try {
                socket.add('viewer-ready');
              } on StateError {
                _interrupted(
                  attempt,
                  'The desktop connection closed during sign-in.',
                );
                return;
              }
            }
            final password = _pendingPassword;
            _pendingPassword = null;
            if (password != null && !_hasSavedPassword) {
              unawaited(_savePassword(password));
            }
            _startPreferredAudio(attempt);
          }
        case 'audioError':
          _audio.playbackFailed(call.arguments);
        case 'resolution':
          final resolution = call.arguments;
          if (!_ended && resolution is String) _resolution.value = resolution;
        case 'stats':
          if (!_ended && call.arguments is String) {
            final stats = jsonDecode(call.arguments as String);
            if (stats is Map<String, dynamic>) _streamStats.value = stats;
          }
        case 'authenticationFailed':
          _end(
            'UltraVNC rejected the connection. Check its service and password on the PC.',
          );
        case 'viewerFailure':
          final reason = switch (call.arguments) {
            'renderer' => 'Android WebView stopped drawing the desktop.',
            'decode' => 'The viewer could not decode a desktop update.',
            'scaleStalled' => 'The desktop stream stalled while changing size.',
            _ => 'The viewer received an unexpected UltraVNC message.',
          };
          _interrupted(attempt, reason);
        case 'scaleUnconfirmed':
          _showMessage('Waiting for UltraVNC to confirm the stream size.');
        case 'disconnected':
          _interrupted(
            attempt,
            _passwordSubmitted && !_connected
                ? 'UltraVNC closed the stream while checking the VNC password.'
                : 'The UltraVNC viewer disconnected.',
          );
      }
    });
    try {
      await bridge.invokeMethod<void>('start');
    } on PlatformException catch (error) {
      if (_isCurrent(attempt)) {
        _end(
          error.message ?? 'The desktop viewer could not start.',
          reconnect: true,
        );
      }
    }
  }

  Future<void> _submitPassword(String value, {bool allowSave = true}) async {
    final attempt = _attempt;
    if (attempt == null ||
        !_isCurrent(attempt) ||
        _passwordSubmitted ||
        value.isEmpty) {
      return;
    }
    _sessionPassword = value;
    setState(() {
      _passwordSubmitted = true;
      _passwordRequired = false;
      _pendingPassword = allowSave && _rememberPassword ? value : null;
    });
    _password.clear();
    _watchHandshake(attempt);
    try {
      await attempt.bridge?.invokeMethod<void>('password', value);
    } on PlatformException {
      if (_isCurrent(attempt)) {
        _end('The viewer could not send the VNC password.', reconnect: true);
      }
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

  void _audioPermissionChanged() {
    final attempt = _attempt;
    if (widget.audioPermission.value != true) {
      _audioStartTimer?.cancel();
      _audio.stop();
    } else if (attempt != null) {
      _startPreferredAudio(attempt);
    }
  }

  void _startPreferredAudio(_DesktopAttempt attempt) {
    if (!_connected ||
        !_audioPreferred ||
        widget.audioPermission.value != true) {
      return;
    }
    // Give the PC time to register viewer-ready before opening its audio stream.
    _audioStartTimer?.cancel();
    _audioStartTimer = Timer(const Duration(milliseconds: 250), () {
      if (_isCurrent(attempt) &&
          _audioPreferred &&
          widget.audioPermission.value == true) {
        _audio.setEnabled(true);
      }
    });
  }

  Future<void> _changeAudioPreference(bool enabled) async {
    _audioStartTimer?.cancel();
    setState(() => _audioPreferred = enabled);
    _audio.setEnabled(enabled);
    try {
      await widget.preferences.saveAudioEnabled(widget.profile.pin, enabled);
    } catch (_) {
      if (mounted && !_ended && _audioPreferred == enabled) {
        _showMessage('The PC audio preference could not be saved.');
      }
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

  Future<void> _changeStream(RemoteDesktopStreamSettings stream) async {
    _stream = stream;
    unawaited(_sendViewerCommand('quality', stream.encode()));
    try {
      await widget.preferences.save(stream);
    } catch (_) {
      if (mounted && _stream == stream) {
        _showMessage('Stream settings could not be saved.');
      }
    }
  }

  Future<void> _changeScreenFit(RemoteDesktopScreenFit fit) async {
    unawaited(_sendViewerCommand('scale', fit.name));
    try {
      await widget.preferences.saveScreenFit(fit);
    } catch (_) {
      if (mounted && _screenFit == fit) {
        _showMessage('Screen scaling could not be saved.');
      }
    }
  }

  void _audioChanged() {
    final error = _audio.error;
    if (mounted && !_ended && error != null) _showMessage(error);
  }

  Future<void> _setWindowFullscreen(bool fullscreen) async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel(
        'dev.tapmypc/app',
      ).invokeMethod<void>('viewerFullscreen', fullscreen);
    } on PlatformException catch (_) {
      if (mounted && !_ended) {
        _showMessage('Could not change full screen mode.');
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

  Future<void> _open(_DesktopAttempt attempt, MethodChannel bridge) async {
    if (!_isCurrent(attempt) || attempt.opening) return;
    attempt.opening = true;
    try {
      try {
        final (stream, fit, audio) = await (
          widget.preferences.load(),
          widget.preferences.loadScreenFit(),
          widget.preferences.loadAudioEnabled(attempt.profile.pin),
        ).wait;
        if (!_isCurrent(attempt)) return;
        _stream = stream;
        _screenFit = fit;
        _audioPreferred = audio;
      } catch (_) {
        if (!_isCurrent(attempt)) return;
        _showMessage('Saved viewer settings could not be loaded.');
      }
      final api = attempt.api = PcApi(attempt.profile);
      final socket = await api.openRemoteDesktop();
      if (!_isCurrent(attempt)) {
        await api.closeRemoteDesktop(socket);
        return;
      }
      attempt.socket = socket;
      _watchHandshake(attempt);
      await bridge.invokeMethod<void>('scale', _screenFit.name);
      if (!_isCurrent(attempt)) return;
      await bridge.invokeMethod<void>('open', _stream.encode());
      await for (final packet in socket) {
        if (!_isCurrent(attempt)) return;
        if (packet is! List<int>) {
          _interrupted(attempt, 'The PC sent an unexpected desktop message.');
          return;
        }
        await bridge.invokeMethod<void>(
          'screen',
          packet is Uint8List ? packet : Uint8List.fromList(packet),
        );
      }
      if (!_isCurrent(attempt)) return;
      final reason = switch (socket.closeCode) {
        WebSocketStatus.normalClosure when _passwordSubmitted && !_connected =>
          'UltraVNC closed the stream while checking the VNC password.',
        WebSocketStatus.normalClosure => 'The PC closed the desktop stream.',
        WebSocketStatus.goingAway => 'The desktop stream stopped responding.',
        _ => 'The desktop connection was interrupted.',
      };
      _interrupted(attempt, reason);
    } on WebSocketException catch (error) {
      if (!_isCurrent(attempt)) return;
      if (attempt.socket != null) {
        _interrupted(attempt, 'The desktop connection was interrupted.');
        return;
      }
      _end(switch (error.httpStatusCode) {
        401 => 'Pair this phone with the PC again.',
        403 => 'Enable Remote Desktop for this phone in TapMyPC on the PC.',
        409 => 'Another Remote Desktop session is still open.',
        503 =>
          'The PC could not reach UltraVNC. Check Configure → Remote Desktop.',
        _ =>
          'Could not open Remote Desktop. Check the PC connection and try again.',
      }, reconnect: error.httpStatusCode != 401 && error.httpStatusCode != 403);
    } on PlatformException {
      if (_isCurrent(attempt)) {
        _interrupted(
          attempt,
          'Android WebView stopped receiving the desktop stream.',
        );
      }
    } on HandshakeException {
      if (_isCurrent(attempt)) {
        _end(
          'TapMyPC could not verify the PC’s TLS identity. Check its connection and pairing.',
        );
      }
    } on Object {
      if (_isCurrent(attempt)) {
        _interrupted(attempt, 'The desktop connection was interrupted.');
      }
    }
  }

  void _interrupted(_DesktopAttempt attempt, String reason) {
    if (!_isCurrent(attempt)) return;
    debugPrint(
      'Remote Desktop: $reason WebSocket close code ${attempt.socket?.closeCode ?? 'unavailable'}.',
    );
    final connectedAt = attempt.connectedAt;
    final stable =
        connectedAt != null &&
        DateTime.now().difference(connectedAt) >= const Duration(seconds: 30);
    if (connectedAt == null || (_autoRecoveryUsed && !stable)) {
      _end(reason, reconnect: true);
      return;
    }

    _autoRecoveryUsed = true;
    setState(_retireAttempt);
    _retryTimer = Timer(const Duration(milliseconds: 1200), () {
      _retryTimer = null;
      if (mounted && !_ended) setState(_beginAttempt);
    });
  }

  void _retireAttempt() {
    final attempt = _attempt;
    _attempt = null;
    _connected = false;
    _passwordRequired = false;
    _passwordSubmitted = false;
    _pendingPassword = null;
    _audioStartTimer?.cancel();
    _audio.stop();
    attempt?.timeout?.cancel();
    attempt?.bridge?.setMethodCallHandler(null);
    final api = attempt?.api;
    if (api != null) unawaited(api.closeRemoteDesktop(attempt?.socket));
  }

  void _stop() {
    if (_ended) return;
    _ended = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _sessionPassword = null;
    _retireAttempt();
    if (_fullscreen) {
      _fullscreen = false;
      unawaited(_setWindowFullscreen(false));
    }
  }

  void _end(String error, {bool reconnect = false}) {
    if (_ended) return;
    _stop();
    if (mounted) {
      setState(() {
        _error = error;
        _canReconnect = reconnect;
      });
    }
  }

  void _retry() {
    if (!_canReconnect || !_ended) return;
    setState(() {
      _ended = false;
      _error = null;
      _canReconnect = false;
      _autoRecoveryUsed = false;
      _resolution.value = null;
      _streamStats.value = {};
      _beginAttempt();
    });
  }

  Future<void> _resetAndRetry() async {
    if (!_canReconnect) return;
    try {
      await widget.preferences.save(const RemoteDesktopStreamSettings());
      if (mounted) _retry();
    } catch (_) {
      if (mounted) _showMessage('Stream settings could not be reset.');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.revision.removeListener(_desktopChanged);
    widget.audioPermission.removeListener(_audioPermissionChanged);
    _audio.removeListener(_audioChanged);
    _stop();
    _audio.dispose();
    if (_orientationOverridden) {
      unawaited(SystemChrome.setPreferredOrientations([]));
    }
    _resolution.dispose();
    _streamStats.dispose();
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

  Widget _audioButton() => ListenableBuilder(
    listenable: Listenable.merge([_audio, widget.audioPermission]),
    builder: (_, _) {
      final permission = widget.audioPermission.value;
      return IconButton(
        tooltip: !_audioPreferred
            ? 'Play PC audio'
            : _audio.enabled
            ? 'Stop PC audio'
            : 'Turn off saved PC audio',
        isSelected: _audioPreferred,
        icon: _audio.connecting
            ? const SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _audio.enabled
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
              ),
        onPressed: !_connected
            ? null
            : () {
                if (_audioPreferred || permission == true) {
                  unawaited(_changeAudioPreference(!_audioPreferred));
                } else {
                  _showMessage(
                    permission == null
                        ? 'Update TapMyPC on the PC to use audio.'
                        : 'Allow audio for this phone in Configure → Authorized phones on the PC.',
                  );
                }
              },
      );
    },
  );

  List<Widget> _viewerButtons() => [
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
    _audioButton(),
  ];

  Widget _landscapeToolbar() => Align(
    alignment: Alignment.topRight,
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_toolbarExpanded) ...[
              ..._viewerButtons(),
              IconButton(
                onPressed: _showOptions,
                tooltip: 'Remote Desktop options',
                icon: const Icon(Icons.more_vert),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'Disconnect',
                icon: const Icon(Icons.close),
              ),
            ],
            IconButton(
              onPressed: () =>
                  setState(() => _toolbarExpanded = !_toolbarExpanded),
              tooltip: _toolbarExpanded
                  ? 'Hide viewer controls'
                  : 'Show viewer controls',
              icon: Icon(_toolbarExpanded ? Icons.chevron_right : Icons.tune),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _streamDetails() => ListenableBuilder(
    listenable: Listenable.merge([_resolution, _streamStats, _audio]),
    builder: (context, _) {
      final stats = _streamStats.value;
      final resolution = _resolution.value;
      final kbps = stats['kbps'];
      final updates = stats['updates'];
      final encodings = stats['encodings'];
      final chroma = stats['jpegChroma'];
      final text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resolution != null)
            Text('Stream resolution  $resolution', style: text.titleMedium),
          if (kbps is int && updates is int)
            Text(
              'Screen receive rate  ${kbps >= 1000 ? '${(kbps / 1000).toStringAsFixed(1)} Mbps' : '$kbps kbps'}'
              ' · $updates updates/s',
              style: text.bodySmall,
            ),
          ExpansionTile(
            title: const Text('Stream details'),
            tilePadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (encodings is List && encodings.isNotEmpty)
                Text('Observed encodings  ${encodings.join(', ')}'),
              if (chroma is String) Text('Observed JPEG chroma  $chroma'),
              if (widget.audioPermission.value == true)
                const Text('PC audio  Opus stereo · 48 kHz · 96 kbps target'),
            ],
          ),
        ],
      );
    },
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
                      child: SegmentedButton<RemoteDesktopScreenFit>(
                        segments: [
                          for (final fit in RemoteDesktopScreenFit.values)
                            ButtonSegment(value: fit, label: Text(fit.label)),
                        ],
                        selected: {_screenFit},
                        onSelectionChanged: (value) {
                          updateSheet(() => _screenFit = value.single);
                          unawaited(_changeScreenFit(value.single));
                        },
                      ),
                    ),
                    Text(
                      _screenFit == RemoteDesktopScreenFit.fit
                          ? 'Show the entire desktop at its original aspect ratio.'
                          : 'Fill the viewer at the original aspect ratio. Drag a scrollbar to reach cropped edges.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    _streamDetails(),
                    const SizedBox(height: 24),
                    RemoteDesktopStreamOptions(
                      settings: _stream,
                      onChanged: (stream) => unawaited(_changeStream(stream)),
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
    final landscape =
        _connected &&
        !_ended &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (_fullscreen != landscape) {
      _fullscreen = landscape;
      if (!landscape) _toolbarExpanded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fullscreen == landscape) {
          unawaited(_setWindowFullscreen(landscape));
        }
      });
    }
    final attempt = _attempt;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: landscape
          ? null
          : AppBar(
              toolbarHeight: 48,
              titleSpacing: 4,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'Disconnect',
                icon: const Icon(Icons.arrow_back),
              ),
              title: Text(widget.profile.name, overflow: TextOverflow.ellipsis),
              actions: [
                if (_connected && !_ended) ..._viewerButtons(),
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
        child: attempt != null && _error == null && Platform.isAndroid
            ? Stack(
                fit: StackFit.expand,
                children: [
                  AndroidView(
                    key: ObjectKey(attempt),
                    viewType: 'dev.tapmypc/remote-desktop-view',
                    onPlatformViewCreated: (id) => _attach(attempt, id),
                  ),
                  if (_passwordRequired)
                    const ColoredBox(color: Colors.black54),
                  if (_passwordRequired) _passwordPanel(),
                  if (landscape) _landscapeToolbar(),
                ],
              )
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error ??
                            (_retryTimer != null
                                ? 'Reconnecting to ${widget.profile.name}…'
                                : 'Remote Desktop is available on Android.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      if (_canReconnect) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _retry,
                          child: const Text('Reconnect'),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_resetAndRetry()),
                          child: const Text(
                            'Reset stream settings and reconnect',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
