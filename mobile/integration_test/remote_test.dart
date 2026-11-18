import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Pinned connection, saved profile, and simulated command on Android',
    (tester) async {
      const address = String.fromEnvironment(
        'TEST_ADDRESS',
        defaultValue: 'https://127.0.0.1:45832',
      );
      const pin = String.fromEnvironment('TEST_PIN');
      const code = String.fromEnvironment('TEST_CODE');
      final wrong = PcApi(
        PcProfile('Wrong identity', address, List.filled(64, '0').join(), ''),
      );
      await expectLater(
        wrong.request(
          '/pair',
          method: 'POST',
          body: {'code': code, 'name': 'Must not enroll'},
        ),
        throwsA(anything),
      );
      wrong.close();
      final enrollment = PcApi(const PcProfile('Simulator', address, pin, ''));
      final result = await enrollment.request(
        '/pair',
        method: 'POST',
        body: {'code': code, 'name': 'Android device test'},
      );
      enrollment.close();
      final profile = PcProfile('Simulator', address, pin, result['token']);
      const store = ProfileStore();
      final previous = await store.load();
      final client = PcApi(profile);
      try {
        await store.save([profile]);
        expect((await store.load()).single.token, profile.token);
        await tester.pumpWidget(const TapMyPcApp());
        for (var i = 0; i < 80; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Connected to Simulator').evaluate().isNotEmpty) break;
        }
        expect(find.text('Connected to Simulator'), findsOneWidget);
        await tester.ensureVisible(find.text('Mute').first);
        await tester.tap(find.text('Mute').first);
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.text('Unmute').evaluate().isNotEmpty) break;
        }
        expect((await client.request('/status'))['audio']['muted'], true);
        expect(find.text('Unmute'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      } finally {
        client.close();
        await store.save(previous);
      }
    },
  );
}
