import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/selected_connection.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native pinned Tailscale and LAN fallback use the same PC identity',
    (tester) async {
      final fixture = Map<String, dynamic>.from(
        jsonDecode(
          utf8.decode(
            base64Decode(const String.fromEnvironment('TEST_NETWORK_FIXTURE')),
          ),
        ),
      );
      final control = HttpClient();
      Future<dynamic> step(String action) async {
        final request = await control.postUrl(
          Uri.parse('${fixture['controlUrl']}/test/$action'),
        );
        request.headers.set('X-Test-Key', fixture['controlKey']);
        final response = await request.close();
        expect(response.statusCode, 200);
        return jsonDecode(await utf8.decoder.bind(response).join());
      }

      final opened = <PcApi>[];
      try {
        var profile = await PairingInvitation.parse(
          fixture['invitation'],
        ).redeem();
        final local = PcApi(profile);
        opened.add(local);
        final status = await local.request('/status');
        profile = local.verifiedProfile.withNetworkHints(
          status['networkConnection'],
        );
        expect(profile.localEndpoint, fixture['wifiAddress']);
        expect(profile.tailscaleEndpoint, fixture['tailscaleAddress']);
        expect(profile.keyPin, isNotNull);
        final automatic = await connectSelectedPc(profile, []);
        opened.add(automatic.api);
        expect(automatic.api.transportLabel, 'Local network');
        final remote = await connectSelectedPc(
          profile.withConnectionMode('tailscale'),
          [],
        );
        opened.add(remote.api);
        expect(remote.api.transportLabel, 'Tailscale');
        expect(remote.profile.keyPin, profile.keyPin);
        expect(remote.profile.token, profile.token);
        await remote.api.request(
          '/audio/mute',
          method: 'PUT',
          body: {'muted': true},
        );
        expect((await step('state'))['audio']['muted'], true);

        final wrong = PcApi(
          PcProfile(
            profile.name,
            fixture['tailscaleAddress'],
            'd' * 64,
            profile.token,
          ),
        );
        opened.add(wrong);
        await expectLater(
          wrong.request('/status'),
          throwsA(isA<HandshakeException>()),
        );
        await step('wifiOff');
        final recovered = await connectSelectedPc(profile, []);
        opened.add(recovered.api);
        expect(recovered.api.transportLabel, 'Tailscale');
        expect(recovered.profile.localEndpoint, profile.localEndpoint);
        expect(recovered.profile.tailscaleEndpoint, profile.tailscaleEndpoint);
        final state = await step('state');
        expect(state['clientDetails'].single['transport'], 'Tailscale');
        await expectLater(
          connectSelectedPc(profile.withConnectionMode('local'), []),
          throwsA(isA<SocketException>()),
        );
        await step('revoke');
        await expectLater(
          connectSelectedPc(profile, []),
          throwsA(
            isA<PcApiException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
      } finally {
        for (final api in opened) {
          api.close();
        }
        await step('stop');
        control.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
