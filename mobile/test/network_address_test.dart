import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';

void main() {
  test(
    'Address changes retain credentials, identity and Bluetooth metadata',
    () {
      final original = PcProfile(
        'My PC',
        'https://192.168.1.10:45831',
        'a' * 64,
        'secret',
        keyPin: 'b' * 64,
        bluetoothAddress: '10:20:30:40:50:60',
        connectionMode: 'bluetooth',
      );
      final updated = original
          .atAddress(networkAddress(' https://100.80.90.100:45831/ '))
          .withConnectionMode('local');
      final saved = PcProfile.fromJson(updated.toJson());
      expect(saved.address, 'https://100.80.90.100:45831');
      expect(saved.pin, original.pin);
      expect(saved.keyPin, original.keyPin);
      expect(saved.token, original.token);
      expect(saved.bluetoothAddress, original.bluetoothAddress);
      expect(saved.connectionMode, 'local');
      final api = PcApi(saved);
      expect(api.transportLabel, 'Tailscale');
      api.close();
    },
  );

  test(
    'Address editor rejects endpoints unsupported by strict Host validation',
    () {
      for (final invalid in [
        'http://100.80.90.100:45831',
        'https://my-pc:45831',
        'https://user:pass@100.80.90.100:45831',
        'https://100.80.90.100:45831/api',
        'https://100.80.90.100:45831?token=x',
        'https://100.80.90.100:45831#fragment',
        'https://100.80.90.100',
        'https://100.80.90.100:99999',
        '',
      ]) {
        expect(
          () => networkAddress(invalid),
          throwsFormatException,
          reason: invalid,
        );
      }
    },
  );
}
