import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/ui/app_theme.dart';
import 'package:tapmypc_mobile/ui/network_address_editor.dart';

void main() {
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
  testWidgets('Tailscale setup accepts bare IP and keeps port under Advanced', (
    tester,
  ) async {
    final pc = PcProfile('PC', 'https://192.168.1.10:45831', 'a' * 64, 'token');
    String? saved;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(AccentPalette.choices.first),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => NetworkAddressEditor(
                  profile: pc,
                  tailscale: true,
                  onSave: (endpoint) async {
                    saved = endpoint;
                    return null;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Tailscale IP'), findsOneWidget);
    expect(find.textContaining('Port 45831'), findsOneWidget);
    expect(find.text('TapMyPC port'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '100.80.90.100');
    await tester.tap(find.text('Verify and save'));
    await tester.pumpAndSettle();
    expect(saved, 'https://100.80.90.100:45831');
  });

  for (final tailscale in [false, true]) {
    testWidgets(
      'Advanced port fits a small phone with large text and keyboard (tailscale=$tailscale)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        addTearDown(tester.view.reset);
        final pc = PcProfile(
          'PC',
          'https://192.168.1.10:45831',
          'a' * 64,
          'token',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(AccentPalette.choices.first),
            builder: (context, child) => RepaintBoundary(
              key: const Key('capture'),
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!,
              ),
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open'),
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => NetworkAddressEditor(
                      profile: pc,
                      tailscale: tailscale,
                      onSave: (_) async => null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final advanced = find.text('Advanced');
        await tester.ensureVisible(advanced);
        await tester.tap(advanced);
        await tester.pumpAndSettle();
        final port = find.widgetWithText(TextFormField, 'TapMyPC port');
        expect(port.hitTestable(), findsOneWidget);
        await tester.enterText(port, '45832');
        expect(find.text('45832'), findsOneWidget);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/mobile-ui/${tailscale ? 'tailscale' : 'local'}-editor-large-text.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
