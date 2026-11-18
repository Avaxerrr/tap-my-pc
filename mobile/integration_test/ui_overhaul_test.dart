import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/pairing_page.dart';
import 'package:tapmypc_mobile/ui/app_theme.dart';
import 'package:tapmypc_mobile/ui/widgets.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Polished Android controls retain pinned targeting and cancellation',
    (tester) async {
      const address = String.fromEnvironment(
        'TEST_ADDRESS',
        defaultValue: 'https://127.0.0.1:45833',
      );
      const pin = String.fromEnvironment('TEST_PIN');
      const code = String.fromEnvironment('TEST_CODE');
      const store = ProfileStore();
      final previous = await store.load();
      final preferred = await store.lastSelected();
      const storage = FlutterSecureStorage();
      final previousAppearance = await storage.read(
        key: AppearanceController.storageKey,
      );
      PcApi? client;
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) return;
        }
        expect(finder, findsWidgets);
      }

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        final bytes = await binding.takeScreenshot(name);
        await File(
          '${Directory.systemTemp.path}/tapmypc-$name.png',
        ).writeAsBytes(bytes);
      }

      try {
        final wrong = PcApi(PcProfile('Wrong identity', address, '0' * 64, ''));
        await expectLater(
          wrong.request(
            '/pair',
            method: 'POST',
            body: {'name': 'Must not enroll', 'code': code},
          ),
          throwsA(anything),
        );
        wrong.close();
        final enrollment = PcApi(
          const PcProfile('Simulator', address, pin, ''),
        );
        final result = await enrollment.request(
          '/pair',
          method: 'POST',
          body: {'name': 'Android UI test', 'code': code},
        );
        enrollment.close();
        final profile = PcProfile('Simulator', address, pin, result['token']);
        client = PcApi(profile);
        await store.save([profile]);
        await store.select(pin);
        await tester.pumpWidget(const TapMyPcApp());
        await waitFor(find.text('Connected to Simulator'));
        final info = await const MethodChannel(
          'dev.tapmypc/app',
        ).invokeMapMethod<String, dynamic>('version');
        expect(
          find.text('v${info!['version']} (build ${info['build']})'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Mute'));
        await tester.tap(find.text('Mute'));
        await waitFor(find.text('Unmute'));
        expect((await client.request('/status'))['audio']['muted'], true);
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await shot('remote');
        await tester.tap(find.text('Devices').last);
        await tester.pumpAndSettle();
        expect(find.text('Main display'), findsOneWidget);
        await shot('devices');
        final bluetooth = find.widgetWithText(SectionCard, 'Bluetooth');
        await tester.ensureVisible(bluetooth);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: bluetooth, matching: find.text('Turn off')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Turn off Bluetooth on Simulator?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
        await tester.pumpAndSettle();
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if ((await client.request('/status'))['bluetooth']['state'] == 'Off') {
            break;
          }
        }
        expect((await client.request('/status'))['bluetooth']['state'], 'Off');
        await tester.tap(find.text('Power').last);
        await tester.pumpAndSettle();
        final timers = find.widgetWithText(SectionCard, 'Set a timer');
        await tester.ensureVisible(timers);
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: timers, matching: find.text('Sleep')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Sleep Simulator?'), findsOneWidget);
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        await waitFor(find.byKey(const Key('pending-action')));
        await shot('power');
        expect(
          (await client.request('/status'))['scheduler']['pending'],
          isNotNull,
        );
        await tester.tap(find.byKey(const Key('cancel-pending')));
        await tester.pumpAndSettle();
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if ((await client.request('/status'))['scheduler']['pending'] == null) {
            break;
          }
        }
        expect(
          (await client.request('/status'))['scheduler']['pending'],
          isNull,
        );
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        await shot('settings');
        await tester.tap(find.text('Mint'));
        await tester.pumpAndSettle();
        expect(
          await storage.read(key: AppearanceController.storageKey),
          contains('Mint'),
        );
        await shot('settings-mint');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('How connections work'));
        await tester.pumpAndSettle();
        expect(find.text('How connections work'), findsOneWidget);
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(AccentPalette.choices.first),
            home: const PairPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Scan PC QR'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await shot('pairing');
        await tester.tap(find.text('Enter details manually'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        client?.close();
        await store.save(previous);
        if (preferred != null) await store.select(preferred);
        if (previousAppearance == null) {
          await storage.delete(key: AppearanceController.storageKey);
        } else {
          await storage.write(
            key: AppearanceController.storageKey,
            value: previousAppearance,
          );
        }
      }
    },
  );
}
