import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/ui/remote_controls.dart';

void main() {
  Future<void> render(
    WidgetTester tester,
    String? state,
    List<bool> sent, {
    bool bluetooth = false,
    bool busy = false,
    bool canControl = true,
    bool offline = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DeviceControls(
              status: offline
                  ? null
                  : {
                      'bluetooth': {'state': state, 'canControl': canControl},
                    },
              monitors: const [],
              busy: busy,
              usingBluetooth: bluetooth,
              send: (_, _, _) async {},
              onBluetooth: (value) async {
                sent.add(value);
              },
              onBrightnessPreview: (_, _) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Wi-Fi shows the PC radio state and only its applicable action', (
    tester,
  ) async {
    final sent = <bool>[];
    await render(tester, 'Off', sent);
    expect(find.text('PC Bluetooth: Off'), findsOneWidget);
    expect(find.text('Turn off'), findsNothing);
    await tester.ensureVisible(find.text('Turn on'));
    await tester.tap(find.text('Turn on'));
    expect(sent, [true]);
    await render(tester, 'On', sent);
    expect(find.text('PC Bluetooth: On'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);
    await tester.ensureVisible(find.text('Turn off'));
    await tester.tap(find.text('Turn off'));
    expect(sent, [true, false]);
  });
  testWidgets(
    'Actual Bluetooth transport disables radio changes and explains switching',
    (tester) async {
      final sent = <bool>[];
      await render(tester, 'On', sent, bluetooth: true);
      expect(
        find.text('Switch to Wi-Fi to change the PC’s Bluetooth.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Turn off'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Turn off'));
      await tester.tap(find.text('Turn off'));
      expect(sent, isEmpty);
    },
  );
  testWidgets(
    'Unknown, unavailable and mixed state cannot offer a guessed action',
    (tester) async {
      final sent = <bool>[];
      for (final state in [null, 'Unavailable', 'Disabled', 'Mixed']) {
        await render(tester, state, sent);
        expect(find.text('Turn on'), findsNothing);
        expect(find.text('Turn off'), findsNothing);
      }
      expect(sent, isEmpty);
    },
  );
  testWidgets('Busy, offline and uncontrollable radios cannot send a change', (
    tester,
  ) async {
    final sent = <bool>[];
    await render(tester, 'On', sent, busy: true);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Turn off'),
          )
          .onPressed,
      isNull,
    );
    await render(tester, 'Off', sent, canControl: false);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Turn on'),
          )
          .onPressed,
      isNull,
    );
    await render(tester, null, sent, offline: true);
    expect(find.text('PC Bluetooth: Unavailable'), findsOneWidget);
    expect(sent, isEmpty);
  });
}
