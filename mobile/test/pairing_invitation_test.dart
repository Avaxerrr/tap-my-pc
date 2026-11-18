import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';

void main() {
  Map<String, dynamic> valid() => {
    'type': 'tapmypc-pair',
    'version': 1,
    'name': 'Home PC',
    'address': 'https://192.168.1.5:45831',
    'fingerprint': List.filled(64, 'a').join(),
    'secret': List.filled(64, 'b').join(),
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  };
  test(
    'Desktop invitation parses with pinned identity and independent secret',
    () {
      final invitation = PairingInvitation.parse(jsonEncode(valid()));
      expect(invitation.name, 'Home PC');
      expect(invitation.secret, List.filled(64, 'b').join());
      expect(invitation.fingerprint, List.filled(64, 'a').join());
    },
  );
  test('Malformed, expired, unencrypted, or unknown QR is rejected', () {
    for (final patch in [
      {'type': 'other'},
      {'version': 2},
      {'address': 'http://192.168.1.5'},
      {'address': 'https://name:password@192.168.1.5'},
      {'fingerprint': 'wrong'},
      {'secret': '123456'},
      {'name': ''},
      {'expiresAt': '2000-01-01T00:00:00Z'},
    ]) {
      expect(
        () => PairingInvitation.parse(jsonEncode({...valid(), ...patch})),
        throwsFormatException,
      );
    }
    expect(() => PairingInvitation.parse('not-json'), throwsFormatException);
  });
  test('Parsing errors do not echo sensitive QR text', () {
    const secret = 'SECRET-DO-NOT-ECHO';
    try {
      PairingInvitation.parse('invalid $secret');
      fail('Expected rejection');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains(secret)));
    }
  });
}
