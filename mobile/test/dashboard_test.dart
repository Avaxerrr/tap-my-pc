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
    bool offline = false,
    bool busy = false,
    bool pending = false,
    double scale = 1,
    Size size = const Size(393, 852),
    List<Object?>? sent,
    ValueChanged<PcProfile>? select,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    final appearance = AppearanceController();
    addTearDown(appearance.dispose);
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
            pending: pending
                ? {
                    'id': 'timer-test',
                    'action': 'Sleep',
                    'dueAt': DateTime.now()
                        .add(const Duration(minutes: 30))
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
            profileStatus: (p) => p == home ? 'Connected' : 'Available',
            onSelect: select ?? (_) {},
            onAdd: () async {},
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
  testWidgets('Empty state and installed version are visible', (tester) async {
    await render(tester, empty: true);
    expect(find.text('Add your PC'), findsOneWidget);
    expect(find.text('v0.4.2 (build 6)'), findsOneWidget);
    await screenshot(tester, 'welcome');
    expect(tester.takeException(), isNull);
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
      await render(tester, select: (p) => selected = p);
      await tester.tap(find.text('Home desktop'));
      await tester.pumpAndSettle();
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
  testWidgets('Small phone and large text keep every tab usable', (
    tester,
  ) async {
    await render(tester, size: const Size(320, 760), scale: 1.8, pending: true);
    expect(tester.takeException(), isNull);
    for (final tab in ['Devices', 'Power', 'Remote']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await screenshot(tester, 'large-text');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
