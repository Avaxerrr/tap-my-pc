import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';
import 'package:tapmypc_mobile/pairing_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Decode desktop QR on Android, pin identity, enroll once, and save profile',
    (tester) async {
      const image = String.fromEnvironment('TEST_QR_IMAGE');
      const pcName = String.fromEnvironment('TEST_PC_NAME');
      final file = File('${Directory.systemTemp.path}/tapmypc-qr-fixture.png');
      await file.writeAsBytes(base64Decode(image));
      final scanner = MobileScannerController(autoStart: false);
      final decoded = await scanner.analyzeImage(
        file.path,
        formats: [BarcodeFormat.qrCode],
      );
      expect(decoded, isNotNull);
      final invitation = PairingInvitation.parse(
        decoded!.barcodes.first.rawValue!,
      );
      expect(invitation.name, pcName);
      final wrong = PcApi(
        PcProfile(
          invitation.name,
          invitation.address,
          List.filled(64, '0').join(),
          '',
        ),
      );
      await expectLater(
        wrong.request(
          '/pair/qr',
          method: 'POST',
          body: {'secret': invitation.secret, 'name': 'Must not enroll'},
        ),
        throwsA(anything),
      );
      wrong.close();
      final profile = await invitation.redeem();
      await expectLater(invitation.redeem(), throwsA(isA<HttpException>()));
      const store = ProfileStore();
      final previous = await store.load();
      try {
        await store.save([profile]);
        expect((await store.load()).single.token, profile.token);
        await tester.pumpWidget(const TapMyPcApp());
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Connected to $pcName').evaluate().isNotEmpty) break;
        }
        expect(find.text('Connected to $pcName'), findsOneWidget);
        await tester.pumpWidget(const MaterialApp(home: PairPage()));
        await tester.pumpAndSettle();
        expect(find.text('Scan PC QR'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        await store.save(previous);
        await file.delete();
      }
    },
  );
}
