import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/ui/remote_desktop_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Reset persists defaults and retires the old low-color mode', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tapmypc.remoteDesktop.stream.v2':
          '{"depth":8,"chroma":"444","preset":"sharper","encoding":"zrle","divisor":2}',
    });
    final preferences = RemoteDesktopPreferences();
    final legacy = await preferences.load();
    expect(legacy.encode(), isNot(contains('"depth"')));
    expect(legacy.encode(), isNot(contains('"chroma"')));
    expect(legacy.encoding, RemoteDesktopEncoding.zrle);
    expect(legacy.divisor, 2);

    await preferences.save(const RemoteDesktopStreamSettings());
    final reset = await RemoteDesktopPreferences().load();
    expect(reset.preset, RemoteDesktopQuality.balanced);
    expect(reset.quality, 6);
    expect(reset.compression, 2);
    expect(reset.encoding, RemoteDesktopEncoding.automatic);
    expect(reset.divisor, 1);
  });

  test('Balanced is default and previous quality choices migrate', () async {
    FlutterSecureStorage.setMockInitialValues({});
    expect(
      (await RemoteDesktopPreferences().load()).preset,
      RemoteDesktopQuality.balanced,
    );
    FlutterSecureStorage.setMockInitialValues({
      'tapmypc.remoteDesktop.quality.v1': 'sharper',
    });
    final previous = await RemoteDesktopPreferences().load();
    expect(previous.preset, RemoteDesktopQuality.sharper);
    expect(previous.quality, 8);
  });

  test(
    'Zero compression is available in Zlib and safe when launching Tight',
    () {
      for (final encoding in [
        RemoteDesktopEncoding.automatic,
        RemoteDesktopEncoding.tight,
      ]) {
        final restored = RemoteDesktopStreamSettings.fromJson({
          'encoding': encoding.id,
          'compression': 0,
        });
        expect(restored.compression, 1);
        expect(restored.encode(), contains('"compression":1'));
      }

      final zlib = RemoteDesktopStreamSettings.fromJson({
        'encoding': 'zlib',
        'compression': 0,
      });
      expect(zlib.encode(), contains('"compression":0'));
      expect(
        zlib.copyWith(encoding: RemoteDesktopEncoding.tight).compression,
        1,
      );
    },
  );

  test('Fill survives reopening and resetting stream settings', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final preferences = RemoteDesktopPreferences();
    expect(await preferences.loadScreenFit(), RemoteDesktopScreenFit.fit);
    final save = preferences.saveScreenFit(RemoteDesktopScreenFit.fill);
    expect(await preferences.loadScreenFit(), RemoteDesktopScreenFit.fill);
    await save;
    await preferences.save(const RemoteDesktopStreamSettings());
    expect(
      await RemoteDesktopPreferences().loadScreenFit(),
      RemoteDesktopScreenFit.fill,
    );
  });

  test(
    'Custom settings survive reopening and presets keep other choices',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final preferences = RemoteDesktopPreferences();
      final custom = (await preferences.load()).copyWith(
        preset: RemoteDesktopQuality.custom,
        quality: 9,
        compression: 4,
        encoding: RemoteDesktopEncoding.zrle,
        divisor: 2,
      );
      final save = preferences.save(custom);
      final loading = preferences.load();
      expect((await loading).encode(), custom.encode());
      await save;
      final restored = await RemoteDesktopPreferences().load();
      expect(restored.encode(), custom.encode());
      final preset = restored.applyPreset(RemoteDesktopQuality.saveData);
      expect(preset.quality, 2);
      expect(preset.compression, 6);
      expect(preset.encoding, RemoteDesktopEncoding.zrle);
      expect(preset.divisor, 2);
    },
  );
}
