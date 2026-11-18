import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';

void main() {
  test(
    'Parallel optional reads share one Bluetooth TLS stream and retain the LAN profile',
    () async {
      final fixture = jsonDecode(
        File('test/fixtures/tls_test_certificates.json').readAsStringSync(),
      )['fixtures']['valid'];
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(fixture['certificate']))
        ..usePrivateKeyBytes(utf8.encode(fixture['privateKey']));
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      final ports = <int>{};
      final paths = <String>[];
      final subscription = server.listen((request) async {
        ports.add(request.connectionInfo!.remotePort);
        paths.add(request.uri.path);
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer isolated-test-token',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'path': request.uri.path}));
        await request.response.close();
      });
      final der = base64Decode(
        (fixture['certificate'] as String).replaceAll(
          RegExp(r'-----[^-]+-----|\s'),
          '',
        ),
      );
      final profile = PcProfile(
        'Saved PC',
        'https://192.0.2.10:45831',
        sha256.convert(der).toString(),
        'isolated-test-token',
        bluetoothAddress: '10:6F:D9:9E:80:F0',
        connectionMode: 'bluetooth',
      );
      final client = PcApi.tunnel(profile, server.port);
      try {
        final results = await Future.wait(
          [
            '/status',
            '/monitors',
            '/audio/outputs',
            '/shortcuts',
          ].map((path) => client.request(path)),
        );
        expect(results, hasLength(4));
        expect(
          ports,
          hasLength(1),
          reason: 'One peer/service must not open concurrent RFCOMM streams.',
        );
        expect(paths.toSet(), hasLength(4));
        expect(paths, hasLength(4));
        expect(client.verifiedProfile.address, profile.address);
        expect(
          client.verifiedProfile.bluetoothAddress,
          profile.bluetoothAddress,
        );
        expect(client.verifiedProfile.connectionMode, 'bluetooth');
        expect(client.verifiedProfile.keyPin, isNotNull);
      } finally {
        client.close();
        await server.close(force: true);
        await subscription.cancel();
      }
    },
  );
}
