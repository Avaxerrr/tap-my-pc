import 'package:flutter/services.dart';

/// Native NSD returns address hints, never authentication decisions.
class PcDiscovery {
  static const _channel = EventChannel('dev.tapmypc/discovery');
  static final _events = _channel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => event as Map<dynamic, dynamic>);
  Stream<Map<dynamic, dynamic>> get events => _events;
}
