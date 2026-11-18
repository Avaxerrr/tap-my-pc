import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';

void main() {
  final pin = List.filled(64, 'a').join();
  final profile = PcProfile(
    'Home',
    'https://192.168.1.2:45831',
    pin,
    'saved-credential',
  );
  test('Only the saved identity can contribute a private address hint', () {
    Map<String, dynamic> event(String address, {String? fingerprint}) => {
      'kind': 'found',
      'fingerprint': fingerprint ?? pin,
      'address': address,
    };
    expect(
      discoveredAddress(profile, event('https://192.168.1.8:45831')),
      'https://192.168.1.8:45831',
    );
    expect(
      discoveredAddress(
        profile,
        event(
          'https://192.168.1.8:45831',
          fingerprint: List.filled(64, 'b').join(),
        ),
      ),
      isNull,
    );
    for (final address in [
      'http://192.168.1.8:45831',
      'https://example.com:45831',
      'https://8.8.8.8:45831',
      'https://user:pass@192.168.1.8:45831',
      'https://192.168.1.8:45831/path',
      'https://192.168.1.8:45831?token=x',
    ]) {
      expect(discoveredAddress(profile, event(address)), isNull);
    }
  });
  test('Address recovery preserves the credential and PC identity', () {
    final moved = profile.atAddress('https://192.168.1.8:45831');
    expect(moved.name, profile.name);
    expect(moved.pin, profile.pin);
    expect(moved.token, profile.token);
    expect(moved.address, isNot(profile.address));
  });
}
