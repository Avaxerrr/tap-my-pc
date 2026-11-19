import 'dart:io';

import 'package:flutter/services.dart';

class WakeOnLanSettings {
  final String mac, destination;
  final int port;

  const WakeOnLanSettings._(this.mac, this.destination, this.port);

  factory WakeOnLanSettings.parse(String mac, String destination, String port) {
    mac = mac.trim();
    if (!RegExp(
      r'^(?:[0-9a-fA-F]{12}|[0-9a-fA-F]{2}([:-])(?:[0-9a-fA-F]{2}\1){4}[0-9a-fA-F]{2})$',
    ).hasMatch(mac)) {
      throw const FormatException(
        'Enter the PC network adapter’s MAC address.',
        'mac',
      );
    }
    mac = mac.replaceAll(RegExp('[:-]'), '').toUpperCase();
    if (mac == '000000000000' ||
        int.parse(mac.substring(0, 2), radix: 16).isOdd) {
      throw const FormatException(
        'Enter the PC network adapter’s MAC address.',
        'mac',
      );
    }
    final ip = InternetAddress.tryParse(destination.trim());
    if (ip == null ||
        ip.type != InternetAddressType.IPv4 ||
        ip.isLoopback ||
        ip.isMulticast ||
        ip.rawAddress.first == 0) {
      throw const FormatException('Enter a local IPv4 address.', 'destination');
    }
    final number = int.tryParse(port.trim(), radix: 10);
    if (number == null || number < 1 || number > 65535) {
      throw const FormatException('Enter a UDP port from 1 to 65535.', 'port');
    }
    final pairs = [
      for (var i = 0; i < mac.length; i += 2) mac.substring(i, i + 2),
    ];
    return WakeOnLanSettings._(pairs.join(':'), ip.address, number);
  }

  static WakeOnLanSettings? fromJson(Object? json) {
    if (json is! Map ||
        json['mac'] is! String ||
        json['destination'] is! String ||
        json['port'] is! int) {
      return null;
    }
    try {
      return WakeOnLanSettings.parse(
        json['mac'],
        json['destination'],
        json['port'].toString(),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WakeOnLanSettings &&
      mac == other.mac &&
      destination == other.destination &&
      port == other.port;

  @override
  int get hashCode => Object.hash(mac, destination, port);

  Map<String, Object> toJson() => {
    'mac': mac,
    'destination': destination,
    'port': port,
  };

  Uint8List magicPacket() {
    final bytes = mac
        .split(':')
        .map((part) => int.parse(part, radix: 16))
        .toList();
    final packet = Uint8List(102)..fillRange(0, 6, 0xff);
    for (var offset = 6; offset < packet.length; offset += bytes.length) {
      packet.setRange(offset, offset + bytes.length, bytes);
    }
    return packet;
  }

  Future<void> send() =>
      const MethodChannel('dev.tapmypc/wake_on_lan').invokeMethod<void>(
        'send',
        {'destination': destination, 'port': port, 'packet': magicPacket()},
      );
}
