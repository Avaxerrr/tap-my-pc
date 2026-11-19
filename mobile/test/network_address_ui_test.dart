import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/main.dart';
import 'package:tapmypc_mobile/ui/app_theme.dart';

final profile = PcProfile(
  'Saved PC',
  'https://192.168.1.10:45831',
  'a' * 64,
  'saved-token',
  keyPin: 'b' * 64,
  bluetoothAddress: '10:20:30:40:50:60',
);
const newAddress = 'https://100.80.90.100:45831';

class AddressApi extends PcApi {
  final bool reject;
  final List<String> calls;
  AddressApi(super.profile, this.calls, {this.reject = false});
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    calls.add('$method ${this.profile.address}$path');
    if (reject) throw const HandshakeException('Wrong PC identity.');
    return switch (path) {
      '/status' => {
        'pcName': profile.name,
        'capabilities': {'audio': false, 'media': false, 'display': false},
        'scheduler': {'pending': null},
      },
      _ => <dynamic>[],
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
    for (final channel in ['dev.tapmypc/discovery', 'dev.tapmypc/app']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  for (final reject in [false, true]) {
    testWidgets('Address editing verifies before saving (reject=$reject)', (
      tester,
    ) async {
      final calls = <String>[];
      final appearance = AppearanceController();
      addTearDown(appearance.dispose);
      await tester.pumpWidget(
        AppearanceScope(
          controller: appearance,
          child: MaterialApp(
            theme: appTheme(AccentPalette.choices.first),
            home: RemotePage(
              createApi: (p) => AddressApi(
                p,
                calls,
                reject: reject && p.address == newAddress,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Connection'));
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Local network address'));
      await tester.tap(find.text('Local network address'));
      await tester.pumpAndSettle();
      expect(find.text('Local IP'), findsOneWidget);
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      expect(find.text('Connection for Saved PC'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);

      await tester.ensureVisible(find.text('Tailscale address'));
      await tester.tap(find.text('Tailscale address'));
      await tester.pumpAndSettle();
      final count = calls.length;
      await tester.pump(const Duration(seconds: 12));
      expect(
        calls.length,
        count,
        reason: 'Background reads pause during editing',
      );
      await tester.enterText(find.byType(TextFormField), newAddress);
      await tester.tap(find.text('Verify and save'));
      await tester.pumpAndSettle();
      final saved = (await const ProfileStore().load()).single;
      expect(saved.localEndpoint, profile.address);
      expect(saved.tailscaleEndpoint, reject ? null : newAddress);
      expect(saved.pin, profile.pin);
      expect(saved.keyPin, profile.keyPin);
      expect(saved.token, profile.token);
      expect(saved.bluetoothAddress, profile.bluetoothAddress);
      expect(
        calls.where((c) => c == 'GET $newAddress/status').length,
        greaterThan(0),
      );
      expect(calls.every((c) => c.startsWith('GET ')), true);
      if (reject) {
        expect(find.textContaining('Address was not saved.'), findsOneWidget);
        expect(find.text(newAddress), findsOneWidget);
        await tester.tap(find.text('Back').last);
        await tester.pumpAndSettle();
      } else {
        expect(saved.connectionMode, 'auto');
        expect(find.text('Address saved.'), findsOneWidget);
        expect(find.text('100.80.90.100'), findsOneWidget);
      }
      expect(find.text('Connection for Saved PC'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      expect(find.text('Accent color'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.text('Connected to Saved PC · Local network'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
