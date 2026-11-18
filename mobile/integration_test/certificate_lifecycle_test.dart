import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import '../test_support/certificate_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native pairing, certificate renewal, restart, identity loss and QR recovery',
    (tester) async {
      final fixture = Map<String, dynamic>.from(
        jsonDecode(
          utf8.decode(
            base64Decode(const String.fromEnvironment('TEST_CERT_FIXTURE')),
          ),
        ),
      );
      const store = ProfileStore();
      final previous = await store.load();
      final selected = await store.lastSelected();
      try {
        await runCertificateScenario(fixture);
        await tester.pumpWidget(const TapMyPcApp());
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find
              .text('Connected to Certificate test PC')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        expect(find.text('Connected to Certificate test PC'), findsOneWidget);
        await tester.tap(find.byTooltip('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Re-pair selected PC'), findsOneWidget);
        final control = HttpClient();
        late Map<String, dynamic> reset;
        try {
          final request = await control.postUrl(
            Uri.parse('${fixture['controlUrl']}/test/reset'),
          );
          request.headers.set('X-Test-Key', fixture['controlKey'] as String);
          final response = await request.close();
          expect(response.statusCode, 200);
          reset = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(response).join()),
          );
        } finally {
          control.close(force: true);
        }
        await tester.tap(find.text('Re-pair selected PC'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'Replace the saved pairing for Certificate test PC',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Enter details manually'));
        await tester.tap(find.text('Enter details manually'));
        await tester.pumpAndSettle();
        for (final entry in {
          'PC name': 'Certificate test PC',
          'HTTPS address': reset['address'] as String,
          'SHA-256 fingerprint': reset['fingerprint'] as String,
          'Pairing code': reset['code'] as String,
        }.entries) {
          final field = find.byWidgetPredicate(
            (widget) =>
                widget is TextField &&
                widget.decoration?.labelText == entry.key,
          );
          await tester.ensureVisible(field);
          await tester.enterText(field, entry.value);
        }
        await tester.ensureVisible(find.text('Pair manually'));
        await tester.tap(find.text('Pair manually'));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find
              .text('Connected to Certificate test PC')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
        expect(find.text('Connected to Certificate test PC'), findsOneWidget);
        final saved = await store.load();
        expect(saved, hasLength(2));
        expect(saved.first.name, 'Other saved PC');
        expect(saved.last.keyPin, reset['keyPin']);
        expect(await store.lastSelected(), saved.last.pin);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
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
