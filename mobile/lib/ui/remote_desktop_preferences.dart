import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum RemoteDesktopQuality {
  saveData('save-data', 'Save data', 2, 6),
  balanced('balanced', 'Balanced', 6, 2),
  sharper('sharper', 'Sharper', 8, 2),
  custom('custom', 'Custom', 6, 2);

  const RemoteDesktopQuality(
    this.id,
    this.label,
    this.quality,
    this.compression,
  );
  final String id, label;
  final int quality, compression;

  static RemoteDesktopQuality parse(Object? id) =>
      values.where((preset) => preset.id == id).firstOrNull ?? balanced;
}

enum RemoteDesktopEncoding {
  automatic('auto', 'Automatic', 'Recommended for most screens'),
  tight('tight', 'Tight', 'Uses less data · fine detail may soften'),
  zrle('zrle', 'ZRLE', 'Full detail · efficient for text'),
  zlib('zlib', 'Zlib', 'Full image detail'),
  hextile('hextile', 'Hextile', 'Full detail · can use more data'),
  rre('rre', 'RRE', 'Full detail · suits simple screens'),
  raw('raw', 'Raw', 'Uncompressed pixels');

  const RemoteDesktopEncoding(this.id, this.label, this.description);
  final String id, label, description;

  bool get usesJpeg => this == automatic || this == tight;
  bool get usesCompressionLevel => usesJpeg || this == zlib;
  int get minimumCompression => usesJpeg ? 1 : 0;
  String get displayName => '$label · $description';
}

enum RemoteDesktopScreenFit {
  fit('Fit'),
  fill('Fill');

  const RemoteDesktopScreenFit(this.label);
  final String label;
}

class RemoteDesktopStreamSettings {
  const RemoteDesktopStreamSettings({
    this.preset = RemoteDesktopQuality.balanced,
    this.quality = 6,
    int compression = 2,
    this.encoding = RemoteDesktopEncoding.automatic,
    this.divisor = 1,
  }) : _compression = compression;

  factory RemoteDesktopStreamSettings.fromJson(Map<String, dynamic> json) {
    final preset = RemoteDesktopQuality.parse(json['preset']);
    int level(String key, int fallback) {
      final value = json[key];
      return value is int && value >= 0 && value <= 9 ? value : fallback;
    }

    return RemoteDesktopStreamSettings(
      preset: preset,
      quality: level('quality', preset.quality),
      compression: level('compression', preset.compression),
      encoding:
          RemoteDesktopEncoding.values
              .where((encoding) => encoding.id == json['encoding'])
              .firstOrNull ??
          RemoteDesktopEncoding.automatic,
      divisor: switch (json['divisor']) {
        2 => 2,
        3 => 3,
        4 => 4,
        _ => 1,
      },
    );
  }

  final RemoteDesktopQuality preset;
  final int quality, _compression, divisor;
  final RemoteDesktopEncoding encoding;

  int get compression => _compression.clamp(encoding.minimumCompression, 9);

  RemoteDesktopStreamSettings applyPreset(RemoteDesktopQuality value) =>
      value == RemoteDesktopQuality.custom
      ? copyWith(preset: value)
      : copyWith(
          preset: value,
          quality: value.quality,
          compression: value.compression,
        );

  RemoteDesktopStreamSettings copyWith({
    RemoteDesktopQuality? preset,
    int? quality,
    int? compression,
    RemoteDesktopEncoding? encoding,
    int? divisor,
  }) => RemoteDesktopStreamSettings(
    preset: preset ?? this.preset,
    quality: quality ?? this.quality,
    compression: compression ?? this.compression,
    encoding: encoding ?? this.encoding,
    divisor: divisor ?? this.divisor,
  );

  String encode() => jsonEncode({
    'preset': preset.id,
    'quality': quality,
    'compression': compression,
    'encoding': encoding.id,
    'divisor': divisor,
  });
}

class RemoteDesktopPreferences {
  RemoteDesktopPreferences([this.storage = const FlutterSecureStorage()]);

  static const _key = 'tapmypc.remoteDesktop.stream.v2';
  static const _legacyKey = 'tapmypc.remoteDesktop.quality.v1';
  static const _screenFitKey = 'tapmypc.remoteDesktop.screenFit';
  static const _audioKeyPrefix = 'tapmypc.remoteDesktop.audio.';
  final FlutterSecureStorage storage;
  Future<void> _writes = Future.value();

  Future<RemoteDesktopStreamSettings> load() async {
    await _writes.catchError((Object _) {});
    final saved = await storage.read(key: _key);
    if (saved != null) {
      final data = jsonDecode(saved);
      if (data is Map<String, dynamic>) {
        return RemoteDesktopStreamSettings.fromJson(data);
      }
    }
    final legacy = await storage.read(key: _legacyKey);
    return const RemoteDesktopStreamSettings().applyPreset(
      RemoteDesktopQuality.parse(legacy),
    );
  }

  Future<RemoteDesktopScreenFit> loadScreenFit() async {
    await _writes.catchError((Object _) {});
    return (await storage.read(key: _screenFitKey)) == 'fill'
        ? RemoteDesktopScreenFit.fill
        : RemoteDesktopScreenFit.fit;
  }

  Future<bool> loadAudioEnabled(String pcPin) async {
    await _writes.catchError((Object _) {});
    return (await storage.read(key: '$_audioKeyPrefix$pcPin')) == 'true';
  }

  Future<void> saveAudioEnabled(String pcPin, bool enabled) =>
      _save('$_audioKeyPrefix$pcPin', enabled.toString());

  Future<void> save(RemoteDesktopStreamSettings value) =>
      _save(_key, value.encode());

  Future<void> saveScreenFit(RemoteDesktopScreenFit value) =>
      _save(_screenFitKey, value.name);

  Future<void> _save(String key, String value) {
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => storage.write(key: key, value: value));
  }
}
