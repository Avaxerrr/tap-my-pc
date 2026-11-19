import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../connection.dart';

class _AudioSession {
  _AudioSession(this.id, PcProfile profile) : api = PcApi(profile);

  final int id;
  final PcApi api;
  WebSocket? socket;
}

class RemoteDesktopAudio extends ChangeNotifier {
  RemoteDesktopAudio(this.profile);

  final PcProfile profile;
  MethodChannel? _bridge;
  _AudioSession? _session;
  int _nextId = 0;
  bool _connecting = false;
  String? _error;

  bool get enabled => _session != null;
  bool get connecting => _connecting;
  String? get error => _error;

  void attach(MethodChannel bridge) => _bridge = bridge;

  void setEnabled(bool enabled) {
    final bridge = _bridge;
    if (!enabled) {
      stop();
    } else if (_session == null && bridge != null) {
      final session = _AudioSession(++_nextId, profile);
      _session = session;
      _connecting = true;
      _error = null;
      notifyListeners();
      unawaited(_play(session, bridge));
    }
  }

  Future<void> _play(_AudioSession session, MethodChannel bridge) async {
    var failure = 'PC audio ended. Turn it on again to retry.';
    try {
      final socket = await session.api.openRemoteDesktopAudio();
      if (!identical(_session, session)) {
        await session.api.closeRemoteDesktop(socket);
        return;
      }
      session.socket = socket;
      await bridge.invokeMethod<void>('startAudio', session.id);
      if (!identical(_session, session)) return;
      _connecting = false;
      notifyListeners();

      await for (final packet in socket) {
        if (!identical(_session, session)) break;
        if (packet is! List<int> || packet.isEmpty || packet.length > 1275) {
          failure = 'The PC sent an invalid audio packet.';
          break;
        }
        await bridge.invokeMethod<void>(
          'audioPacket',
          packet is Uint8List ? packet : Uint8List.fromList(packet),
        );
      }
      if (socket.closeCode == WebSocketStatus.internalServerError) {
        failure = 'Windows could not capture the default audio output.';
      }
    } on WebSocketException catch (error) {
      failure = switch (error.httpStatusCode) {
        403 =>
          'Allow audio for this phone in Configure → Authorized phones on the PC.',
        409 => 'PC audio is busy or the viewer is still connecting. Try again.',
        _ => 'Could not connect to PC audio. Try again.',
      };
    } on PlatformException {
      failure = 'This phone could not play PC audio.';
    } catch (_) {
      failure = 'Could not connect to PC audio. Try again.';
    } finally {
      if (identical(_session, session)) _finish(failure);
    }
  }

  void playbackFailed(Object? sessionId) {
    if (_session?.id == sessionId && _session != null) {
      _finish('This phone could not play PC audio.');
    }
  }

  void stop() => _finish(null);

  void _finish(String? failure) {
    final session = _session;
    if (session == null) return;
    _session = null;
    _connecting = false;
    _error = failure;
    unawaited(session.api.closeRemoteDesktop(session.socket));
    final stopped = _bridge?.invokeMethod<void>('stopAudio', session.id);
    if (stopped != null) unawaited(stopped.catchError((Object _) {}));
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
