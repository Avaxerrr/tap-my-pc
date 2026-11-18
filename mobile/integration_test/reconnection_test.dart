import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/discovery.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Discover, pair once, recover saved PC address, and remember selection',
    (tester) async {
      const store = ProfileStore();
      final previous = await store.load();
      final preferred = await store.lastSelected();
      final file = File(
        '${Directory.systemTemp.path}/tapmypc-reconnect-qr.png',
      );
      final scanner = MobileScannerController(autoStart: false);
      try {
        await file.writeAsBytes(
          base64Decode(const String.fromEnvironment('TEST_QR_IMAGE')),
        );
        final decoded = await scanner.analyzeImage(
          file.path,
          formats: [BarcodeFormat.qrCode],
        );
        final invitation = PairingInvitation.parse(
          decoded!.barcodes.first.rawValue!,
        );
        final events = <Map<dynamic, dynamic>>[];
        final sub = PcDiscovery().events.listen(events.add);
        for (var i = 0; i < 160; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (events.any(
            (e) =>
                discoveredAddress(
                  PcProfile(
                    invitation.name,
                    invitation.address,
                    invitation.fingerprint,
                    '',
                  ),
                  e,
                ) !=
                null,
          )) {
            break;
          }
        }
        final hints = events.where((e) => e['kind'] == 'found').toList();
        expect(
          hints.any(
            (e) =>
                e['address'] ==
                const String.fromEnvironment('TEST_LAN_ADDRESS'),
          ),
          isTrue,
          reason:
              'Native Android NSD must discover the real desktop advertisement.',
        );
        await sub.cancel();
        final profile = await invitation.redeem();
        final wrong = PcApi(
          PcProfile(
            profile.name,
            profile.address,
            List.filled(64, '0').join(),
            profile.token,
          ),
        );
        await expectLater(wrong.request('/status'), throwsA(anything));
        wrong.close();
        await expectLater(invitation.redeem(), throwsA(isA<HttpException>()));
        final stale = profile.atAddress('https://127.0.0.1:45834');
        final other = PcProfile(
          'Other saved PC',
          'https://127.0.0.1:45835',
          List.filled(64, '1').join(),
          'unused',
        );
        await store.save([other, stale]);
        await store.select(profile.pin);
        await tester.pumpWidget(const TapMyPcApp());
        for (var i = 0; i < 250; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Connected to ${profile.name}').evaluate().isNotEmpty) {
            break;
          }
        }
        expect(find.text('Connected to ${profile.name}'), findsOneWidget);
        final saved = (await store.load()).firstWhere(
          (p) => p.pin == profile.pin,
        );
        expect(saved.address, const String.fromEnvironment('TEST_LAN_ADDRESS'));
        expect(saved.token, profile.token);
        expect(await store.lastSelected(), normalizePin(profile.pin));
        await tester.tap(find.byTooltip('How connections work'));
        await tester.pumpAndSettle();
        expect(find.text('How connections work'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await store.save(previous);
        await store.select(preferred ?? '');
        await scanner.dispose();
        if (await file.exists()) await file.delete();
      }
    },
  );
}
