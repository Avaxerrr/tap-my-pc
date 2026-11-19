import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/ui/remote_desktop_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Quality starts at Balanced and the last choice survives reopening',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final preferences = RemoteDesktopPreferences();
      expect(await preferences.loadQuality(), RemoteDesktopQuality.balanced);

      final saveData = preferences.saveQuality(RemoteDesktopQuality.saveData);
      final sharper = preferences.saveQuality(RemoteDesktopQuality.sharper);
      expect(await preferences.loadQuality(), RemoteDesktopQuality.sharper);
      await Future.wait([saveData, sharper]);

      expect(
        await RemoteDesktopPreferences().loadQuality(),
        RemoteDesktopQuality.sharper,
      );
    },
  );
}
