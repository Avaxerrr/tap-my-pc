import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/ui/app_theme.dart';

const profile = PcProfile(
  'Test desktop',
  'https://192.168.0.239:45831',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test-credential-never-sent',
);

class FakePcApi extends PcApi {
  FakePcApi() : super(profile);
  final failures = <String, Object>{};
  final calls = <String>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    calls.add('$method $path');
    if (failures[path] case final error?) throw error;
    return switch (path) {
      '/status' => {
        'pcName': profile.name,
        'capabilities': {'audio': true, 'media': true, 'display': true},
        'audio': {'volume': 35, 'muted': false},
        'bluetooth': {'state': 'On', 'canControl': true},
        'scheduler': {'pending': null},
      },
      '/audio/outputs' => [
        {'id': 'speakers', 'name': 'Test speakers', 'isDefault': true},
      ],
      '/monitors' => [
        {
          'id': 'screen',
          'name': 'Test monitor',
          'canSetBrightness': false,
          'canSetPower': false,
        },
      ],
      '/shortcuts' => [],
      _ => throw StateError('Unexpected request: $method $path'),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'tapmypc.profiles.v1': jsonEncode([profile.toJson()]),
      'tapmypc.selected.v1': profile.pin,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tapmypc/discovery'),
          (_) async => null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.tapmypc/app'),
          (_) async => {'version': 'test', 'build': 7},
        );
  });
  Future<void> render(WidgetTester tester, FakePcApi api) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(AccentPalette.choices.first),
        home: RemotePage(createApi: (_) => api),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final route in ['/monitors', '/audio/outputs', '/shortcuts']) {
    testWidgets(
      '$route failure keeps reachable PC connected and other controls enabled',
      (tester) async {
        final api = FakePcApi()
          ..failures[route] = PcApiException(
            500,
            'Windows could not complete this command.',
          );
        await render(tester, api);
        expect(find.text('Connected to Test desktop'), findsOneWidget);
        expect(find.text('Offline'), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Mute'),
              )
              .onPressed,
          isNotNull,
        );
        if (route == '/monitors') {
          await tester.tap(find.text('Devices').last);
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              'Individual display controls could not be loaded (HTTP 500)',
            ),
            findsOneWidget,
          );
          expect(find.text('Bluetooth'), findsOneWidget);
        } else {
          final warning = find.textContaining(
            route == '/shortcuts'
                ? 'Shortcuts could not be loaded'
                : 'Audio outputs could not be loaded',
          );
          await tester.ensureVisible(warning);
          expect(warning, findsOneWidget);
        }
        expect(api.calls.where((c) => !c.startsWith('GET ')), isEmpty);
        expect(tester.takeException(), isNull);
        await dispose(tester);
      },
    );
  }

  testWidgets('Revoked credentials on a device request still require pairing', (
    tester,
  ) async {
    final api = FakePcApi()
      ..failures['/monitors'] = PcApiException(401, 'Pair this device.');
    await render(tester, api);
    expect(
      find.textContaining('Pairing required. Scan a new QR'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Mute'))
          .onPressed,
      isNull,
    );
    final calls = api.calls.length;
    await tester.pump(const Duration(seconds: 12));
    expect(api.calls.length, calls);
    await dispose(tester);
  });

  testWidgets('Failed status keeps controls offline', (tester) async {
    final api = FakePcApi()
      ..failures['/status'] = const SocketException('PC cannot be reached.');
    await render(tester, api);
    expect(find.text('Offline'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Mute'))
          .onPressed,
      isNull,
    );
    expect(api.calls, ['GET /status']);
    await dispose(tester);
  });

  testWidgets(
    'Device errors recover on existing polling without replaying commands',
    (tester) async {
      final api = FakePcApi()
        ..failures['/monitors'] = PcApiException(500, 'Device read failed.');
      await render(tester, api);
      await tester.tap(find.text('Devices').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Individual display controls could not be loaded'),
        findsOneWidget,
      );
      api.failures.clear();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('Connected to Test desktop'), findsOneWidget);
      expect(find.text('Test monitor'), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(api.calls.where((c) => !c.startsWith('GET ')), isEmpty);
      await dispose(tester);
    },
  );
}
