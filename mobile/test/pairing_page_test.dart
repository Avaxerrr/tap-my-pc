import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';
import 'package:tapmypc_mobile/pairing_page.dart';

void main() {
  testWidgets('A scanned PC has one primary pairing action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<PcProfile>(builder: (_) => const PairPage()),
            ),
            child: const Text('Add a PC'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Add a PC'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Scan PC QR'), findsOneWidget);
    expect(find.text('Enter details manually'), findsOneWidget);

    Future<void> finishScan(PairingInvitation? scanned) async {
      await tester.pumpAndSettle();
      final scanner = tester.element(find.byType(ScanPairPage));
      Navigator.of(scanner).pop(scanned);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Scan PC QR'));
    await finishScan(
      PairingInvitation(
        'Home desktop',
        'https://192.168.0.10:45831',
        'a' * 64,
        'b' * 64,
        DateTime.now().add(const Duration(minutes: 5)),
      ),
    );

    expect(find.text('Home desktop'), findsOneWidget);
    expect(find.text('https://192.168.0.10:45831'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Pair with this PC'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextButton, 'Scan a different QR'),
      findsOneWidget,
    );
    expect(find.text('Enter details manually'), findsNothing);

    await tester.tap(find.text('Scan a different QR'));
    await finishScan(null);
    expect(find.text('Home desktop'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Home desktop'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Scan PC QR'), findsOneWidget);
    await tester.tap(find.text('Enter details manually'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets);
  });
}
