import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/ui/app_theme.dart';
import 'package:tapmypc_mobile/ui/remote_dashboard.dart';
import 'package:tapmypc_mobile/ui/widgets.dart';

const home = PcProfile(
  'Home desktop',
  'https://192.168.0.239:45831',
  'home-pin',
  'not-a-real-token',
);
const laptop = PcProfile(
  'Work laptop',
  'https://192.168.0.240:45831',
  'work-pin',
  'not-a-real-token',
);
Map<String, dynamic> sampleStatus() => {
  'audio': {'volume': 35, 'muted': false},
  'pcName': 'Home desktop',
  'serverVersion': '0.3.1+4',
  'capabilities': {
    'audio': true,
    'media': true,
    'display': true,
    'sleep': true,
    'hibernate': true,
  },
  'bluetooth': {'state': 'On', 'canControl': true},
  'activity': [
    {'message': 'Volume up key sent', 'phase': 'Requested'},
  ],
};

class _MonitoringApi extends PcApi {
  _MonitoringApi()
    : super(
        const PcProfile(
          'Home desktop',
          'https://192.168.0.239:45831',
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'test-token',
        ),
      );

  int calls = 0;

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    expect(path, '/monitoring');
    calls++;
    return {
      'stale': false,
      'snapshot': {
        'generatedAtUtc': '2026-11-19T08:00:00Z',
        'refreshIntervalMs': 2000,
        'metrics': [
          {
            'label': 'CPU Load',
            'group': 'CPU',
            'value': '15%',
            'available': true,
            'defaultVisible': true,
          },
          {
            'label': 'Average Clock',
            'group': 'CPU',
            'value': '3250 MHz',
            'available': true,
            'defaultVisible': false,
          },
        ],
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/Inter_18pt-$weight.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<void> screenshot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 220));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('../artifacts/mobile-ui/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pump();
  }

  Future<AppearanceController> render(
    WidgetTester tester, {
    bool empty = false,
    Future<void> Function()? add,
    bool offline = false,
    bool busy = false,
    bool pending = false,
    Duration pendingRemaining = const Duration(minutes: 30),
    String? transport,
    AccentPalette? accent,
    double scale = 1,
    Size size = const Size(393, 852),
    List<Object?>? sent,
    ValueChanged<PcProfile>? select,
    PcApi? monitoringApi,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
    if (accent != null) await appearance.setAccent(accent);
    await tester.pumpWidget(
      AppearanceScope(
        controller: appearance,
        child: MaterialApp(
          theme: appTheme(appearance.palette),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: RepaintBoundary(key: const Key('capture'), child: child!),
          ),
          home: RemoteDashboard(
            profiles: empty ? [] : [home, laptop],
            selected: empty ? null : home,
            status: empty || offline ? null : sampleStatus(),
            message: empty
                ? 'Add your first PC to get started.'
                : offline
                ? 'Connection unavailable. Check the PC and your Wi-Fi.'
                : 'Connected to Home desktop',
            appVersion: 'v0.4.2 (build 6)',
            discoveryMessage: 'Automatically looking for saved PCs nearby.',
            busy: busy,
            connectionTransport: transport,
            monitoringApi: monitoringApi,
            pending: pending
                ? {
                    'id': 'timer-test',
                    'action': 'Sleep',
                    'dueAt': DateTime.now()
                        .add(pendingRemaining)
                        .toUtc()
                        .toIso8601String(),
                  }
                : null,
            outputs: const [
              {'id': 'speakers', 'name': 'Desktop speakers', 'isDefault': true},
              {'id': 'headphones', 'name': 'Headphones', 'isDefault': false},
            ],
            monitors: const [
              {
                'id': 'main',
                'name': 'Main display',
                'brightness': 60,
                'canSetBrightness': true,
                'canSetPower': true,
              },
              {
                'id': 'other',
                'name': 'Secondary display',
                'canSetBrightness': false,
                'canSetPower': false,
                'message': 'Brightness is unavailable on this display.',
              },
            ],
            shortcuts: const [
              {'id': 'spotify', 'name': 'Spotify', 'kind': 'App'},
              {'id': 'youtube', 'name': 'YouTube', 'kind': 'Website'},
            ],
            profileStatus: (p) => p == home
                ? (offline ? PcAvailability.offline : PcAvailability.connected)
                : PcAvailability.available,
            onSelect: select ?? (_) {},
            onAdd: add ?? () async {},
            onForget: () async {},
            onRefresh: () async {},
            onHelp: () {},
            send: (path, method, body) async {
              sent?.add([path, method, body]);
            },
            power: (action, {delay}) async {
              sent?.add([action, delay]);
            },
            onBluetooth: (value) async {
              sent?.add(value);
            },
            onVolumePreview: (_) {},
            onBrightnessPreview: (_, _) {},
          ),
        ),
      ),
    );
    if (busy) {
      await tester.pump(const Duration(milliseconds: 220));
    } else {
      await tester.pumpAndSettle();
    }
    return appearance;
  }

  test('Appearance persists independently of saved PC credentials', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tapmypc.profiles.v1': 'unchanged',
      'tapmypc.selected.v1': 'home',
    });
    final appearance = AppearanceController();
    await appearance.setAccent(AccentPalette.choices[4]);

    final restored = AppearanceController();
    await restored.load();
    expect(restored.palette.name, 'Amber');

    expect(
      await const FlutterSecureStorage().read(key: 'tapmypc.profiles.v1'),
      'unchanged',
    );
    expect(
      await const FlutterSecureStorage().read(key: 'tapmypc.selected.v1'),
      'home',
    );
    appearance.dispose();
    restored.dispose();
  });
  test('Legacy motion values do not discard saved accents', () async {
    FlutterSecureStorage.setMockInitialValues({
      AppearanceController.storageKey: '{"accent":"Mint","motion":"Off"}',
    });
    final appearance = AppearanceController();
    await appearance.load();
    expect(appearance.palette.name, 'Mint');
    await appearance.setAccent(AccentPalette.choices.last);
    final saved = await const FlutterSecureStorage().read(
      key: AppearanceController.storageKey,
    );
    expect(saved, contains('Amber'));
    expect(saved, isNot(contains('motion')));
    appearance.dispose();
  });
  testWidgets('Stats polls only on its tab and can expand the default view', (
    tester,
  ) async {
    final api = _MonitoringApi();
    addTearDown(api.close);
    await render(tester, monitoringApi: api);
    expect(api.calls, 0);

    await tester.tap(find.text('Stats'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.text('CPU Load'), findsOneWidget);
    expect(find.text('Average Clock'), findsNothing);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Average Clock'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(api.calls, 2);
    await tester.tap(find.text('Remote'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls, 2);
  });

  testWidgets('App transitions follow changes to Android reduced motion', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      AppearanceController.storageKey: '{"accent":"Mint","motion":"On"}',
    });
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearAccessibilityFeaturesTestValue);
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    await tester.pumpWidget(const TapMyPcApp());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      Duration.zero,
    );
    expect(
      MediaQuery.disableAnimationsOf(
        tester.element(find.byType(RemoteDashboard)),
      ),
      isTrue,
    );
    dispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .themeAnimationDuration,
      const Duration(milliseconds: 180),
    );
    expect(
      MediaQuery.disableAnimationsOf(
        tester.element(find.byType(RemoteDashboard)),
      ),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Selected navigation icons stay white in every accent', (
    tester,
  ) async {
    for (final palette in AccentPalette.choices) {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(palette),
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune),
                  label: 'Remote',
                ),
                NavigationDestination(
                  icon: Icon(Icons.devices_outlined),
                  label: 'Devices',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.tune))).color,
        Colors.white,
        reason:
            '${palette.name} selected icon must contrast with its highlight',
      );
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.devices_outlined))).color,
        AppColors.secondary,
      );
    }
  });
  testWidgets('Welcome focuses on pairing and keeps version in About', (
    tester,
  ) async {
    var adds = 0;
    await render(
      tester,
      empty: true,
      add: () async {
        adds++;
      },
    );
    expect(find.text('Connect your PC'), findsOneWidget);
    expect(find.text('Add your PC'), findsOneWidget);
    expect(find.byKey(const Key('app-version')), findsNothing);
    expect(find.text('Your PCs, together.'), findsNothing);
    expect(find.text('Add your first PC to get started.'), findsNothing);
    await screenshot(tester, 'welcome');
    await tester.tap(find.text('Add your PC'));
    expect(adds, 1);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final about = find.text('About TapMyPC');
    await tester.ensureVisible(about);
    await tester.tap(about);
    await tester.pumpAndSettle();
    expect(find.text('0.4.2 (build 6)'), findsOneWidget);
    expect(find.text('PC host'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Welcome remains usable on a small phone with large text', (
    tester,
  ) async {
    var adds = 0;
    await render(
      tester,
      empty: true,
      size: const Size(320, 640),
      scale: 1.8,
      add: () async {
        adds++;
      },
    );
    await tester.ensureVisible(find.text('Add your PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your PC'));
    expect(adds, 1);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'welcome-large-text');
  });
  testWidgets(
    'Remote controls route explicit actions and open the output sheet',
    (tester) async {
      final sent = <Object?>[];
      await render(tester, sent: sent);
      await screenshot(tester, 'remote');
      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(sent.last, [
        '/audio/mute',
        'PUT',
        {'muted': true},
      ]);
      await tester.ensureVisible(find.text('Desktop speakers'));
      await tester.tap(find.text('Desktop speakers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Headphones'));
      await tester.pumpAndSettle();
      expect(sent.last, [
        '/audio/output',
        'PUT',
        {'id': 'headphones'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Navigation groups devices and power; pending cancellation stays visible',
    (tester) async {
      final sent = <Object?>[];
      await render(tester, sent: sent, pending: true);
      await tester.tap(find.text('Devices').last);
      await tester.pumpAndSettle();
      expect(find.text('Displays'), findsOneWidget);
      await screenshot(tester, 'devices');
      await tester.tap(find.text('Power').last);
      await tester.pumpAndSettle();
      expect(find.text('Set a timer'), findsOneWidget);
      await screenshot(tester, 'power');
      await tester.tap(find.byKey(const Key('cancel-pending')));
      await tester.pump();
      expect(sent.last, ['/power/timer-test', 'DELETE', null]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'PC selection preserves target identity and is disabled while busy',
    (tester) async {
      PcProfile? selected;
      await render(tester, offline: true, select: (p) => selected = p);
      await tester.tap(find.text('Home desktop'));
      await tester.pumpAndSettle();
      final dots = tester.widgetList<Icon>(find.byIcon(Icons.circle));
      expect(dots.map((dot) => dot.color), [
        AppColors.offline,
        AppColors.online,
      ]);
      expect(find.text('Offline / searching'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      await screenshot(tester, 'pc-picker');
      await tester.tap(find.text('Work laptop'));
      await tester.pumpAndSettle();
      expect(selected, same(laptop));
      selected = null;
      await render(tester, busy: true, select: (p) => selected = p);
      await tester.tap(find.text('Home desktop'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Your PCs'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Offline controls cannot send commands and retain pending information',
    (tester) async {
      final sent = <Object?>[];
      await render(tester, offline: true, pending: true, sent: sent);
      await tester.tap(find.text('Mute'));
      await tester.tap(find.byKey(const Key('cancel-pending')));
      expect(sent, isEmpty);
      expect(find.byKey(const Key('pending-action')), findsOneWidget);
      await screenshot(tester, 'offline');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('A due offline timer stops occupying the navigation area', (
    tester,
  ) async {
    await render(
      tester,
      offline: true,
      pending: true,
      pendingRemaining: const Duration(seconds: -1),
    );
    expect(find.byKey(const Key('pending-action')), findsNothing);
    await render(
      tester,
      pending: true,
      pendingRemaining: const Duration(seconds: -1),
    );
    expect(find.text('Sleep · Request is due'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Connection badge icons and labels use the neutral foreground', (
    tester,
  ) async {
    final badge = find.byType(StatusBadge);
    for (final (transport, label, background, border, icon) in [
      (
        'Local network',
        'Wi-Fi',
        const Color(0xff182c24),
        const Color(0xff365647),
        Icons.wifi,
      ),
      (
        'Tailscale',
        'Tailscale',
        const Color(0xff29223a),
        const Color(0xff53426d),
        null,
      ),
      (
        'Bluetooth',
        'Bluetooth',
        const Color(0xff14263b),
        const Color(0xff344f71),
        Icons.bluetooth,
      ),
    ]) {
      for (final accent in AccentPalette.choices) {
        await render(tester, transport: transport, accent: accent);
        final text = find.descendant(of: badge, matching: find.text(label));
        expect(tester.widget<Text>(text).style?.color, AppColors.text);
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: badge,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration.color, background);
        expect(decoration.border, Border.all(color: border));
        if (icon == null) {
          final image = tester.widget<Image>(
            find.descendant(of: badge, matching: find.byType(Image)),
          );
          expect(
            (image.image as AssetImage).assetName,
            'assets/icons/tailscale.png',
          );
          expect(image.color, AppColors.text);
        } else {
          final marker = find.descendant(
            of: badge,
            matching: find.byIcon(icon),
          );
          expect(tester.widget<Icon>(marker).color, AppColors.text);
        }
      }
    }
    for (final (offline, busy, label, icon) in [
      (true, false, 'Offline', Icons.link_off),
      (true, true, 'Working', Icons.hourglass_empty),
      (false, false, 'Connected', Icons.link),
    ]) {
      await render(
        tester,
        offline: offline,
        busy: busy,
        transport: offline ? 'Bluetooth' : null,
      );
      final text = find.descendant(of: badge, matching: find.text(label));
      final marker = find.descendant(of: badge, matching: find.byIcon(icon));
      expect(tester.widget<Text>(text).style?.color, AppColors.text);
      expect(tester.widget<Icon>(marker).color, AppColors.text);
      expect(find.text('Bluetooth'), findsNothing);
    }
  });

  testWidgets(
    'A timer takes editable minutes or seconds and observes action minimums',
    (tester) async {
      final sent = <Object?>[];
      await render(tester, sent: sent);
      await tester.tap(find.text('Power').last);
      await tester.pumpAndSettle();
      final duration = find.byKey(const Key('timer-duration'));
      final unit = find.byKey(const Key('timer-unit'));
      final sleep = find.byKey(const Key('timer-Sleep'));
      final restart = find.byKey(const Key('timer-Restart'));
      await tester.ensureVisible(duration);
      expect(find.text('30'), findsOneWidget);
      await tester.enterText(duration, '2');
      await tester.pumpAndSettle();
      await tester.ensureVisible(sleep);
      await tester.tap(sleep);
      expect(sent.single, ['Sleep', 120]);

      await tester.ensureVisible(unit);
      await tester.tap(unit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seconds').last);
      await tester.pumpAndSettle();
      expect(tester.widget<ActionTile>(sleep).onPressed, isNull);
      await tester.ensureVisible(duration);
      await tester.enterText(duration, '3');
      await tester.pumpAndSettle();
      expect(tester.widget<ActionTile>(restart).onPressed, isNull);
      await tester.ensureVisible(sleep);
      await tester.tap(sleep);
      expect(sent.last, ['Sleep', 3]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Settings exposes saved accents and version without a motion override',
    (tester) async {
      final appearance = await render(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await screenshot(tester, 'settings');
      await tester.tap(find.text('Mint'));
      await tester.pumpAndSettle();
      expect(appearance.palette.name, 'Mint');
      expect(find.text('Animations'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('About copies versions and opens setup and GitHub links', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    String? copied;
    String? appAction;
    const appChannel = MethodChannel('dev.tapmypc/app');
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = call.arguments['text'] as String;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(appChannel, (call) async {
      appAction = call.method;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(appChannel, null);
    });

    await render(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final about = find.text('About TapMyPC');
    await tester.ensureVisible(about);
    await tester.tap(about);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about-version')), findsOneWidget);
    expect(find.text('0.3.1 (build 4)'), findsOneWidget);
    await tester.tap(find.text('Copy version info'));
    await tester.pumpAndSettle();
    expect(
      copied,
      'TapMyPC Android app: 0.4.2 (build 6)\nTapMyPC PC host: 0.3.1 (build 4)',
    );
    expect(find.text('Version info copied.'), findsOneWidget);

    await tester.tap(find.text('Setup guide'));
    await tester.pumpAndSettle();
    expect(find.textContaining('open Pair a Phone.'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    final repository = find.text('GitHub repository');
    await tester.ensureVisible(repository);
    await tester.tap(repository);
    await tester.pumpAndSettle();
    expect(appAction, 'openRepository');

    final credit = find.text('Developed by @Avaxerrr');
    await tester.ensureVisible(credit);
    await tester.tap(credit);
    await tester.pumpAndSettle();
    expect(appAction, 'openDeveloperProfile');
  });

  testWidgets('Small phone and large text keep every tab usable', (
    tester,
  ) async {
    final api = _MonitoringApi();
    addTearDown(api.close);
    await render(
      tester,
      size: const Size(320, 760),
      scale: 1.8,
      pending: true,
      monitoringApi: api,
    );
    expect(tester.takeException(), isNull);
    for (final tab in ['Devices', 'Power', 'Stats', 'Remote']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await screenshot(tester, 'large-text');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
