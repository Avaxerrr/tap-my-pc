import 'dart:convert';
import 'connection.dart';

class PairingInvitation {
  final String name, address, fingerprint, secret;
  final DateTime expiresAt;
  const PairingInvitation(
    this.name,
    this.address,
    this.fingerprint,
    this.secret,
    this.expiresAt,
  );

  factory PairingInvitation.parse(String raw, {DateTime? now}) {
    try {
      if (raw.length > 4096) throw const FormatException();
      final j = jsonDecode(raw);
      if (j is! Map ||
          j['type'] != 'tapmypc-pair' ||
          j['version'] != 1 ||
          j['name'] is! String ||
          j['address'] is! String ||
          j['fingerprint'] is! String ||
          j['secret'] is! String ||
          j['expiresAt'] is! String) {
        throw const FormatException();
      }
      final name = (j['name'] as String).trim();
      final address = j['address'] as String;
      final fingerprint = normalizePin(j['fingerprint']);
      final secret = j['secret'] as String;
      final expiry = DateTime.parse(j['expiresAt']).toUtc();
      if (name.isEmpty ||
          name.length > 60 ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(secret)) {
        throw const FormatException();
      }
      // Reuse endpoint and pin validation without performing any network IO.
      final validator = PcApi(PcProfile(name, address, fingerprint, ''));
      validator.close();
      if (!expiry.isAfter(now ?? DateTime.now())) {
        throw const FormatException(
          'This QR expired. Generate a new one on the PC.',
        );
      }
      return PairingInvitation(name, address, fingerprint, secret, expiry);
    } on FormatException catch (e) {
      if (e.message.startsWith('This QR expired')) rethrow;
      throw const FormatException(
        'Not a supported TapMyPC pairing QR. Generate one in the PC app.',
      );
    } catch (_) {
      throw const FormatException(
        'Not a supported TapMyPC pairing QR. Generate one in the PC app.',
      );
    }
  }

  Future<PcProfile> redeem() async {
    if (!expiresAt.isAfter(DateTime.now())) {
      throw const FormatException(
        'This QR expired. Generate a new one on the PC.',
      );
    }
    final client = PcApi(PcProfile(name, address, fingerprint, ''));
    try {
      final result = await client.request(
        '/pair/qr',
        method: 'POST',
        body: {'secret': secret, 'name': 'TapMyPC Android'},
      );
      final token = result['token'];
      if (token is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) {
        throw const FormatException(
          'The PC returned an invalid pairing response.',
        );
      }
      return PcProfile(name, address, fingerprint, token);
    } finally {
      client.close();
    }
  }
}
