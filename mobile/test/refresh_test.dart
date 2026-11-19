import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/ui/app_theme.dart';
import 'package:tapmypc_mobile/ui/widgets.dart';

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
  Map<String, dynamic>? networkConnection;
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
        if (networkConnection != null) 'networkConnection': networkConnection,
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

  testWidgets(
    'Connection dialog pauses background reads and keeps pairing on cancel',
    (tester) async {
      final api = FakePcApi();
      final appearance = AppearanceController();
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            theme: appTheme(AccentPalette.choices.first),
            home: RemotePage(createApi: (_) => api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Connection'));
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();
      expect(find.text('Automatic'), findsOneWidget);
      expect(find.text('Bluetooth only'), findsOneWidget);
      final before = api.calls.length;
      await tester.pump(const Duration(seconds: 12));
      expect(api.calls.length, before);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Connected to Test desktop · Local network'), findsOneWidget);
      expect(api.calls.length, greaterThan(before));
      final saved = await const ProfileStore().load();
      expect(saved.single.token, profile.token);
      expect(saved.single.pin, profile.pin);
      expect(api.calls.where((c) => !c.startsWith('GET ')), isEmpty);
      await dispose(tester);
    },
  );

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
        expect(find.text('Connected to Test desktop · Local network'), findsOneWidget);
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

  testWidgets('Offline PC sends one saved wake packet and waits for status', (
    tester,
  ) async {
    final api = FakePcApi()
      ..failures['/status'] = const SocketException('PC cannot be reached.');
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    final messages = <MethodCall>[];
    const channel = MethodChannel('dev.tapmypc/wake_on_lan');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      messages.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: MaterialApp(
          theme: appTheme(AccentPalette.choices.first),
          home: RemotePage(createApi: (_) => api),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Wake PC'), findsNothing);
    await tester.tap(find.text('Power').last);
    await tester.pumpAndSettle();
    expect(find.text('Wake settings'), findsNothing);
    expect(find.text('Wake-on-LAN'), findsNothing);
    final powerGrid = find.ancestor(
      of: find.text('Lock'),
      matching: find.byType(ActionGrid),
    );
    expect(
      find.descendant(of: powerGrid, matching: find.text('Wake PC')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Wake PC'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Wake-on-LAN'));
    await tester.tap(find.widgetWithText(ListTile, 'Wake-on-LAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter the PC network adapter’s MAC address.'),
      findsOneWidget,
    );
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '02-12-34-56-78-9a');
    await tester.enterText(fields.at(1), '192.168.0.255');
    await tester.enterText(fields.at(2), '7');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await const ProfileStore().load()).single;
    expect(saved.token, profile.token);
    expect(
      saved.atAddress('https://192.168.0.15:45831').wakeOnLan?.mac,
      '02:12:34:56:78:9A',
    );
    await tester.tap(find.text('Wake PC'));
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(
      find.textContaining('Wake packet sent to Test desktop'),
      findsOneWidget,
    );
    expect(messages.single.method, 'send');
    expect(messages.single.arguments, {
      'destination': '192.168.0.255',
      'port': 7,
      'packet': [
        ...List.filled(6, 0xff),
        for (var repeat = 0; repeat < 16; repeat++) ...[
          0x02,
          0x12,
          0x34,
          0x56,
          0x78,
          0x9a,
        ],
      ],
    });

    api.networkConnection = {
      'wakeOnLan': {
        'mac': '02:00:00:00:00:01',
        'destination': '192.168.0.191',
        'port': 9,
      },
    };
    api.failures.clear();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Test desktop is back online.'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Wake PC'),
          )
          .onPressed,
      isNull,
    );
    final detected = (await const ProfileStore().load()).single;
    expect(detected.automaticWakeOnLan?.destination, '192.168.0.191');
    expect(detected.effectiveWakeOnLan?.destination, '192.168.0.255');
    expect(messages, hasLength(1));
    expect(api.calls.where((call) => !call.startsWith('GET ')), isEmpty);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Wake-on-LAN'));
    await tester.tap(find.widgetWithText(ListTile, 'Wake-on-LAN'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use automatic'));
    await tester.pumpAndSettle();
    final automatic = (await const ProfileStore().load()).single;
    expect(automatic.wakeOnLan, isNull);
    expect(automatic.effectiveWakeOnLan?.destination, '192.168.0.191');

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Wake-on-LAN'));
    await tester.tap(find.widgetWithText(ListTile, 'Wake-on-LAN'));
    await tester.pumpAndSettle();
    expect(
      find.text('Detected from Test desktop. Edit to override.'),
      findsOneWidget,
    );
    expect(find.text('192.168.0.191'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
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
      expect(find.text('Connected to Test desktop · Local network'), findsOneWidget);
      expect(find.text('Test monitor'), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(api.calls.where((c) => !c.startsWith('GET ')), isEmpty);
      await dispose(tester);
    },
  );
}
