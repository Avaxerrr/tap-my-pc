import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/home_screen.dart';
import 'package:tapmypc_mobile/wake_on_lan.dart';

class StatusApi extends PcApi {
  final List<String> calls;
  bool closed = false;
  StatusApi(super.profile, this.calls);

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    calls.add('$method $path ${profile.address}');
    if (profile.address == 'https://192.168.0.11:45831') {
      throw const SocketException('Unavailable');
    }
    return <String, dynamic>{};
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const desktop = PcProfile(
    'Home desktop',
    'https://192.168.0.10:45831',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'desktop-token',
  );
  final laptop = PcProfile(
    'Laptop',
    'https://192.168.0.11:45831',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'laptop-token',
    tailscaleAddress: 'https://100.80.90.11:45831',
    wakeOnLan: WakeOnLanSettings.parse(
      '00:11:22:33:44:55',
      '192.168.0.255',
      '9',
    ),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'tapmypc.profiles.v1': jsonEncode([desktop.toJson(), laptop.toJson()]),
      'tapmypc.selected.v1': desktop.pin,
    });
  });

  test('Widget setup gets names and opaque IDs only', () async {
    final result = await executeHomeAction(['profiles']);
    final profiles = (result['profiles']! as List).cast<Map>();
    expect(profiles.map((p) => p['name']), ['Home desktop', 'Laptop']);
    expect(profiles.map((p) => p['id']), [
      homeProfileId(desktop),
      homeProfileId(laptop),
    ]);
    expect(profiles.every((p) => p.length == 2), isTrue);
    expect(homeProfileId(laptop), isNot(laptop.pin));
    expect(
      homeProfileId(laptop.atAddress('https://192.168.0.55:45831')),
      homeProfileId(laptop),
    );
  });

  test(
    'Wake sends one packet for the bound PC and rejects a stale ID',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('dev.tapmypc/wake_on_lan');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      final sent = await executeHomeAction(['wake', homeProfileId(laptop)]);
      expect(sent['message'], 'Wake packet sent');
      expect(calls, hasLength(1));
      expect(calls.single.arguments['destination'], '192.168.0.255');
      expect(calls.single.arguments['packet'], laptop.wakeOnLan!.magicPacket());

      final missing = await executeHomeAction(['wake', 'missing-profile']);
      expect(missing['message'], contains('no longer paired'));
      expect(calls, hasLength(1));
    },
  );

  test('Refresh uses only saved network routes for its bound PC', () async {
    final calls = <String>[];
    final clients = <StatusApi>[];
    final status = await executeHomeAction(
      ['refresh', homeProfileId(laptop)],
      createApi: (profile) {
        final client = StatusApi(profile, calls);
        clients.add(client);
        return client;
      },
    );
    expect(status['name'], 'Laptop');
    expect(status['message'], 'Online · Tailscale');
    expect(calls, [
      'GET /status https://192.168.0.11:45831',
      'GET /status https://100.80.90.11:45831',
    ]);
    expect(clients.every((client) => client.closed), isTrue);
  });
}
