import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/certificate_identity.dart';

void main() {
  final data =
      jsonDecode(
            File('test/fixtures/tls_test_certificates.json').readAsStringSync(),
          )['fixtures']
          as Map<String, dynamic>;

  String keyFor(String name) {
    final pem = data[name]['certificate'] as String;
    return certificateKeyPin(
      base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')),
    );
  }

  Future<void> check(
    String served,
    String pinned, {
    required bool accepted,
    String? keyPin,
    bool desktop = false,
  }) async {
    final fixture = data[served] as Map<String, dynamic>;
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(fixture['certificate'] as String))
      ..usePrivateKeyBytes(utf8.encode(fixture['privateKey'] as String));
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final requests = <HttpRequest>[];
    final subscription = server.listen(
      (request) async {
        requests.add(request);
        if (desktop) {
          final viewer = await WebSocketTransformer.upgrade(request);
          viewer.add([82, 70, 66]);
          await viewer.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"pcName":"TLS test"}');
        await request.response.close();
      },
      onError: (Object _) {
        // Rejected handshakes are expected; no HTTP request should arrive.
      },
    );
    final pem = data[pinned]['certificate'] as String;
    final der = base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));
    final api = PcApi(
      PcProfile(
        'TLS test',
        'https://127.0.0.1:${server.port}',
        sha256.convert(der).toString(),
        'TEST-CREDENTIAL-NEVER-SEND-TO-WRONG-IDENTITY',
        keyPin: keyPin,
      ),
    );
    try {
      if (accepted) {
        if (desktop) {
          final viewer = await api.openRemoteDesktop();
          expect(await viewer.first, [82, 70, 66]);
          await viewer.close();
          expect(requests.single.uri.path, '/api/v1/remote-desktop');
          expect(requests.single.uri.hasQuery, isFalse);
        } else {
          expect((await api.request('/status'))['pcName'], 'TLS test');
        }
        expect(requests, hasLength(1));
        expect(api.verifiedProfile.keyPin, keyFor(served));
        expect(
          requests.single.headers.value(HttpHeaders.authorizationHeader),
          'Bearer TEST-CREDENTIAL-NEVER-SEND-TO-WRONG-IDENTITY',
        );
      } else {
        await expectLater(
          desktop ? api.openRemoteDesktop() : api.request('/status'),
          throwsA(anything),
        );
        expect(
          requests,
          isEmpty,
          reason: 'No HTTP request or bearer token may reach this identity.',
        );
      }
    } finally {
      api.close();
      await server.close(force: true);
      await subscription.cancel();
    }
  }

  // These tests use real sockets rather than Flutter's mocked HTTP client.
  test(
    'Remote Desktop upgrades only after authenticating the pinned PC',
    () async {
      await check('valid', 'valid', accepted: true, desktop: true);
      await check('replacement', 'valid', accepted: false, desktop: true);
    },
  );
  test('Valid pinned certificate allows authenticated status', () async {
    await check('valid', 'valid', accepted: true);
  });
  test(
    'Replacement certificate receives no credential until explicitly trusted',
    () async {
      await check('replacement', 'valid', accepted: false);
      await check('replacement', 'replacement', accepted: true);
    },
  );
  test('Expired certificate is rejected even with the matching pin', () async {
    await check('expired', 'expired', accepted: false);
    await check('expired', 'valid', keyPin: keyFor('expired'), accepted: false);
  });
  test('Future certificate is rejected even with the matching pin', () async {
    await check('future', 'future', accepted: false);
    await check('future', 'valid', keyPin: keyFor('future'), accepted: false);
  });
}
