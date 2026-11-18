import 'package:flutter/services.dart';

String? cleanPhoneName(String? value) {
  final name = value?.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  if (name == null || name.isEmpty) return null;
  final result = StringBuffer();
  var length = 0;
  for (final rune in name.runes) {
    final character = String.fromCharCode(rune);
    if (length + character.length > 60) break;
    result.write(character);
    length += character.length;
  }
  final cleaned = result.toString().trim();
  return cleaned.isEmpty ? null : cleaned;
}

class PhoneIdentity {
  static const _channel = MethodChannel('dev.tapmypc/app');
  static Future<String?>? _cached;
  static Future<String?> name() => _cached ??= _read();
  static void refresh() => _cached = null;
  static Future<String?> _read() async {
    try {
      return cleanPhoneName(await _channel.invokeMethod<String>('deviceName'));
    } catch (_) {
      return null;
    }
  }
}
