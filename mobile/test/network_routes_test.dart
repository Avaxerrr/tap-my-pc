import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/selected_connection.dart';

const lan = 'https://192.168.1.10:45831';
const tail = 'https://100.80.90.100:45831';
final pc = PcProfile(
  'One PC',
  lan,
  'a' * 64,
  'same-token',
  keyPin: 'b' * 64,
  bluetoothAddress: '10:20:30:40:50:60',
  tailscaleAddress: tail,
);

class RouteApi extends PcApi {
  final Object? failure;
  final bool bt;
  final List<String> calls;
  RouteApi(super.profile, this.calls, {this.failure, this.bt = false});
  @override
  bool get isBluetooth => bt;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    calls.add('$method ${bt ? 'Bluetooth' : profile.address}$path');
    if (failure != null) throw failure!;
    return {'pcName': 'One PC'};
  }
}

void main() {
  test(
    'Automatic tries LAN then Tailscale before Bluetooth and retains both',
    () async {
      final calls = <String>[];
      var btCalls = 0;
      final result = await connectSelectedPc(
        pc,
        [],
        wifi: (p) => RouteApi(
          p,
          calls,
          failure: p.address == lan ? const SocketException('No LAN') : null,
        ),
        bluetooth: (p) {
          btCalls++;
          return RouteApi(p, calls, bt: true);
        },
      );
      expect(calls, ['GET $lan/status', 'GET $tail/status']);
      expect(btCalls, 0);
      expect(result.profile.localEndpoint, lan);
      expect(result.profile.tailscaleEndpoint, tail);
      expect(result.profile.pin, pc.pin);
      expect(result.profile.token, pc.token);
      result.api.close();
    },
  );

  for (final mode in ['local', 'tailscale']) {
    test('$mode only cannot fall back to another route', () async {
      final calls = <String>[];
      await expectLater(
        connectSelectedPc(
          pc.withConnectionMode(mode),
          [lan, tail],
          wifi: (p) =>
              RouteApi(p, calls, failure: const SocketException('Unavailable')),
          bluetooth: (_) => throw StateError('Must not use Bluetooth'),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(calls, ['GET ${mode == 'local' ? lan : tail}/status']);
    });
  }

  test(
    'Automatic reuses active Bluetooth when higher priority routes fail',
    () async {
      final calls = <String>[];
      final active = RouteApi(pc, calls, bt: true);
      final result = await connectSelectedPc(
        pc,
        [],
        activeApi: active,
        wifi: (p) =>
            RouteApi(p, calls, failure: const SocketException('Unavailable')),
        bluetooth: (_) =>
            throw StateError('Do not open a second RFCOMM stream'),
      );
      expect(identical(result.api, active), true);
      expect(calls, [
        'GET $lan/status',
        'GET $tail/status',
        'GET Bluetooth/status',
      ]);
      result.api.close();
    },
  );

  test('Revocation stops before trying Tailscale or Bluetooth', () async {
    final calls = <String>[];
    await expectLater(
      connectSelectedPc(
        pc,
        [],
        wifi: (p) =>
            RouteApi(p, calls, failure: PcApiException(401, 'Revoked')),
        bluetooth: (_) => throw StateError('No fallback after revocation'),
      ),
      throwsA(isA<PcApiException>()),
    );
    expect(calls, ['GET $lan/status']);
  });

  test('Old combined-network profiles migrate without credential changes', () {
    for (final address in [lan, tail]) {
      final migrated = PcProfile.fromJson({
        'name': pc.name,
        'address': address,
        'pin': pc.pin,
        'keyPin': pc.keyPin,
        'token': pc.token,
        'connectionMode': 'wifi',
      });
      expect(migrated.connectionMode, address == lan ? 'local' : 'tailscale');
      expect(migrated.token, pc.token);
      expect(migrated.pin, pc.pin);
      expect(migrated.keyPin, pc.keyPin);
    }
  });

  test(
    'Authenticated hints update separate slots without switching active route',
    () {
      final learned = pc.withNetworkHints({
        'localAddress': 'https://192.168.1.11:45840',
        'tailscaleAddress': 'https://100.80.90.101:45840',
      });
      expect(learned.address, lan);
      expect(learned.localEndpoint, 'https://192.168.1.11:45840');
      expect(learned.tailscaleEndpoint, 'https://100.80.90.101:45840');
      final ignored = learned.withNetworkHints({
        'localAddress': 'https://evil.example:45831',
        'tailscaleAddress': 'http://100.80.90.100:45831',
      });
      expect(ignored.localEndpoint, learned.localEndpoint);
      expect(ignored.tailscaleEndpoint, learned.tailscaleEndpoint);
      final roundtrip = PcProfile.fromJson(learned.toJson()).atAddress(tail);
      expect(roundtrip.localEndpoint, learned.localEndpoint);
      expect(roundtrip.tailscaleEndpoint, tail);
      expect(roundtrip.token, pc.token);
    },
  );

  test('Bare IP uses known port and explicit advanced port is validated', () {
    expect(
      configuredNetworkAddress('100.80.90.100', pc, tailscale: true),
      tail,
    );
    expect(
      configuredNetworkAddress(
        '100.80.90.100',
        pc,
        tailscale: true,
        port: '45840',
      ),
      'https://100.80.90.100:45840',
    );
    expect(
      () => configuredNetworkAddress('100.80.90.100', pc, tailscale: false),
      throwsFormatException,
    );
    expect(
      () => configuredNetworkAddress('192.168.1.10', pc, tailscale: true),
      throwsFormatException,
    );
    expect(
      () => configuredNetworkAddress(
        '100.80.90.100',
        pc,
        tailscale: true,
        port: 'bad',
      ),
      throwsFormatException,
    );
  });
}
