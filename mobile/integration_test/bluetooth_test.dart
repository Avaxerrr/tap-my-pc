import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/bluetooth_connection.dart';
import 'package:tapmypc_mobile/selected_connection.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';
import 'package:tapmypc_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Actual encrypted Bluetooth, Wi-Fi fallback, timers, reconnect and revocation',
    (tester) async {
      final fixture = Map<String, dynamic>.from(
        jsonDecode(
          utf8.decode(
            base64Decode(
              const String.fromEnvironment('TEST_BLUETOOTH_FIXTURE'),
            ),
          ),
        ),
      );
      const store = ProfileStore();
      final previous = await store.load();
      final selected = await store.lastSelected();
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

      PcApi? api;
      try {
        final profile = await PairingInvitation.parse(
          fixture['invitation'],
        ).redeem();
        final wifi = PcApi(profile);
        final status = await wifi.request('/status');
        wifi.close();
        expect(status['bluetoothConnection']['available'], true);
        final saved = profile.withBluetoothAddress(
          status['bluetoothConnection']['address'],
        );
        await store.save([saved]);
        await store.select(saved.pin);
        expect(await PhoneBluetooth.requestAccess(), true);

        // TLS and bearer verification happen over physical RFCOMM, not an adb-forwarded API port.
        api = BluetoothPcApi(saved);
        expect((await api.request('/status'))['audio']['volume'], 35);
        expect(api.verifiedProfile.keyPin, saved.keyPin);
        await api.request('/audio/mute', method: 'PUT', body: {'muted': true});
        expect((await api.request('/status'))['audio']['muted'], true);
        final timer = await api.request(
          '/power',
          method: 'POST',
          body: {'action': 'Sleep', 'delaySeconds': 1800, 'confirmed': true},
        );
        final timerId = timer['id'];
        expect(timerId, isNotNull);
        expect((await step('state'))['pending']['id'], timerId);
        await api.request('/power/$timerId', method: 'DELETE');

        final wrong = BluetoothPcApi(
          PcProfile(
            saved.name,
            saved.address,
            List.filled(64, '0').join(),
            saved.token,
            bluetoothAddress: saved.bluetoothAddress,
          ),
        );
        try {
          await expectLater(wrong.request('/status'), throwsA(anything));
        } finally {
          wrong.close();
        }

        await step('wifiOff');
        api.close();
        final recovered = await connectSelectedPc(saved, [saved.address]);
        api = recovered.api;
        expect(api.isBluetooth, true);
        expect((await api.request('/status'))['audio']['muted'], true);
        await api.request('/media', method: 'POST', body: {'action': 'Next'});
        expect((await step('state'))['mediaCount'], 1);

        api.close();
        await step('restartBluetooth');
        api = BluetoothPcApi(saved);
        expect((await api.request('/status'))['audio']['muted'], true);
        expect(
          (await step('state'))['mediaCount'],
          1,
          reason: 'Reconnect must not replay media commands.',
        );

        await store.save([saved.withConnectionMode('bluetooth')]);
        await tester.pumpWidget(const TapMyPcApp());
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find
              .text('Connected to Bluetooth test PC · Bluetooth')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        expect(
          find.text('Connected to Bluetooth test PC · Bluetooth'),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connection'));
        await tester.pumpAndSettle();
        expect(find.text('Current: Bluetooth'), findsOneWidget);
        expect(find.text('Automatic'), findsOneWidget);
        await tester.tap(find.text('Wi-Fi only'));
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Offline').evaluate().isNotEmpty) break;
        }
        expect(find.text('Offline'), findsOneWidget);
        expect((await store.load()).single.connectionMode, 'wifi');
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Connection'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bluetooth only'));
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find
              .text('Connected to Bluetooth test PC · Bluetooth')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        expect(
          find.text('Connected to Bluetooth test PC · Bluetooth'),
          findsOneWidget,
        );
        expect((await store.load()).single.connectionMode, 'bluetooth');
        expect((await step('state'))['mediaCount'], 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await step('revoke');
        await expectLater(
          api.request('/status'),
          throwsA(
            isA<PcApiException>().having((e) => e.statusCode, 'status', 401),
          ),
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        api?.close();
        control.close(force: true);
        await store.save(previous);
        if (selected != null) {
          await store.select(selected);
        } else {
          await store.storage.delete(key: 'tapmypc.selected.v1');
        }
      }
    },
  );
}
