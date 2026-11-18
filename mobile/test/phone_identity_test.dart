import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/phone_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.tapmypc/app');
  setUp(() => PhoneIdentity.refresh());
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('Device name is bounded, readable and retains non-ASCII characters', () {
    expect(cleanPhoneName('  My\nPOCO  '), 'My POCO');
    expect(cleanPhoneName('我的手機'), '我的手機');
    expect(cleanPhoneName('  '), isNull);
    expect(cleanPhoneName(List.filled(50, '😀').join())!.length, 60);
  });
  test('Uses native phone identity and refreshes after resume', () async {
    var name = 'POCO X6 5G';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'deviceName');
          return name;
        });
    expect(await PhoneIdentity.name(), name);
    name = 'Renamed phone';
    PhoneIdentity.refresh();
    expect(await PhoneIdentity.name(), name);
  });
  test(
    'Unavailable native identity does not inject a generic name hint',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'unavailable'),
          );
      expect(await PhoneIdentity.name(), isNull);
    },
  );
}
