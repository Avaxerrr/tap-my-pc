import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/selected_connection.dart';

class TransportFake extends PcApi {
  TransportFake(super.profile, {this.failure, this.bluetooth = false});
  final Object? failure;
  final bool bluetooth;
  int statuses = 0, commands = 0;
  bool closed = false;
  @override
  bool get isBluetooth => bluetooth;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    if (path == '/status') {
      statuses++;
      if (failure != null) throw failure!;
      return {'pcName': 'Selected PC'};
    }
    commands++;
    throw const SocketException('Command response lost after sending.');
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  final profile = PcProfile(
    'Selected PC',
    'https://192.168.1.8:45831',
    List.filled(64, 'a').join(),
    'saved-selected-token',
    bluetoothAddress: '10:6F:D9:9E:80:F0',
  );
  test('Automatic prefers Wi-Fi and preserves the explicit target', () async {
    var bluetoothCalls = 0;
    final result = await connectSelectedPc(
      profile,
      [profile.address],
      wifi: (p) => TransportFake(p),
      bluetooth: (p) {
        bluetoothCalls++;
        return TransportFake(p, bluetooth: true);
      },
    );
    expect(bluetoothCalls, 0);
    expect(result.api.isBluetooth, false);
    expect(result.profile.pin, profile.pin);
    expect(result.profile.token, profile.token);
    result.api.close();
  });
  test(
    'Automatic recovers status over Bluetooth without replaying a command',
    () async {
      final wifi = TransportFake(
        profile,
        failure: const SocketException('Wi-Fi lost'),
      );
      final bluetooth = TransportFake(profile, bluetooth: true);
      final result = await connectSelectedPc(
        profile,
        [profile.address],
        wifi: (_) => wifi,
        bluetooth: (_) => bluetooth,
      );
      expect(wifi.closed, true);
      expect(result.api.isBluetooth, true);
      await expectLater(
        result.api.request('/media', method: 'POST', body: {'action': 'Next'}),
        throwsA(isA<SocketException>()),
      );
      expect(bluetooth.commands, 1);
      expect(wifi.commands, 0);
      expect(bluetooth.statuses, 1);
      result.api.close();
    },
  );
  test('Revocation never falls back to another transport', () async {
    var bluetoothCalls = 0;
    await expectLater(
      connectSelectedPc(
        profile,
        [profile.address],
        wifi: (p) => TransportFake(p, failure: PcApiException(401, 'Revoked')),
        bluetooth: (p) {
          bluetoothCalls++;
          return TransportFake(p, bluetooth: true);
        },
      ),
      throwsA(isA<PcApiException>()),
    );
    expect(bluetoothCalls, 0);
  });
  test('Wi-Fi only cannot silently use Bluetooth', () async {
    var bluetoothCalls = 0;
    await expectLater(
      connectSelectedPc(
        profile.withConnectionMode('wifi'),
        [profile.address],
        wifi: (p) =>
            TransportFake(p, failure: const SocketException('Offline')),
        bluetooth: (p) {
          bluetoothCalls++;
          return TransportFake(p, bluetooth: true);
        },
      ),
      throwsA(isA<SocketException>()),
    );
    expect(bluetoothCalls, 0);
  });
  test('Bluetooth only does not probe or send anything over Wi-Fi', () async {
    var wifiCalls = 0;
    final result = await connectSelectedPc(
      profile.withConnectionMode('bluetooth'),
      [profile.address],
      wifi: (p) {
        wifiCalls++;
        return TransportFake(p);
      },
      bluetooth: (p) => TransportFake(p, bluetooth: true),
    );
    expect(wifiCalls, 0);
    expect(result.profile.bluetoothAddress, profile.bluetoothAddress);
    result.api.close();
  });
  test(
    'Old profiles default to Automatic and transport survives secure roundtrip',
    () {
      expect(
        PcProfile.fromJson({
          'name': profile.name,
          'address': profile.address,
          'pin': profile.pin,
          'token': profile.token,
        }).connectionMode,
        'auto',
      );
      final saved = profile
          .withConnectionMode('bluetooth')
          .withKeyPin(List.filled(64, 'c').join());
      final moved = PcProfile.fromJson(
        saved.toJson(),
      ).atAddress('https://192.168.1.9:45831');
      expect(moved.bluetoothAddress, saved.bluetoothAddress);
      expect(moved.connectionMode, 'bluetooth');
      expect(moved.keyPin, saved.keyPin);
    },
  );
}
