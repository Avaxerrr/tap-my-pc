import 'dart:async';
import 'package:flutter/services.dart';
import 'connection.dart';

class PhoneBluetooth {
  static const channel = MethodChannel('dev.tapmypc/bluetooth');
  static Future<bool> requestAccess() async =>
      await channel.invokeMethod<bool>('requestAccess') ?? false;
  static Future<void> openSettings() => channel.invokeMethod<void>('settings');
}

/// Native RFCOMM carries opaque TLS bytes; all identity/authentication remains in PcApi.
class BluetoothPcApi extends PcApi {
  BluetoothPcApi(super.profile);
  Future<Map<dynamic, dynamic>>? _opening;
  PcApi? _inner;
  bool _closed = false;
  @override
  String get transportLabel => 'Bluetooth';
  @override
  bool get isBluetooth => true;
  @override
  PcProfile get verifiedProfile => _inner?.verifiedProfile ?? profile;

  Future<PcApi> _client() async {
    if (_closed) throw StateError('Bluetooth connection was closed.');
    if (_inner != null) return _inner!;
    if (profile.bluetoothAddress == null) {
      throw const FormatException(
        'Connect to this PC over a network once to enable Bluetooth.',
      );
    }
    final open = _opening ??= PhoneBluetooth.channel
        .invokeMapMethod<dynamic, dynamic>('open', {
          'address': profile.bluetoothAddress,
        })
        .then(
          (value) => value ?? (throw StateError('Bluetooth could not start.')),
        );
    final tunnel = await open;
    if (_closed) throw StateError('Bluetooth connection was closed.');
    return _inner ??= PcApi.tunnel(profile, tunnel['port'] as int);
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    try {
      return await (await _client()).request(path, method: method, body: body);
    } catch (error) {
      if (error is PcApiException) rethrow;
      if (_opening != null && !_closed) {
        String? detail;
        try {
          final tunnel = await _opening!;
          detail = await PhoneBluetooth.channel.invokeMethod<String>('error', {
            'id': tunnel['id'],
          });
        } catch (_) {}
        if (detail != null) throw FormatException(detail);
      }
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    super.close();
    _inner?.close();
    unawaited(
      _opening
              ?.then((tunnel) async {
                await PhoneBluetooth.channel.invokeMethod<void>('close', {
                  'id': tunnel['id'],
                });
              })
              .catchError((Object _) {}) ??
          Future<void>.value(),
    );
  }
}
