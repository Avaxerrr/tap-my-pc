import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';

void main() {
  test('Fingerprints normalize without changing identity', () {
    expect(normalizePin('AA:bb CC-DD'), 'aabbccdd');
  });
  test('Unsecured endpoints and invalid identities are rejected', () {
    expect(
      () => PcApi(const PcProfile('PC', 'http://localhost:45831', '', '')),
      throwsFormatException,
    );
    expect(
      () => PcApi(const PcProfile('PC', 'https://localhost:45831', 'bad', '')),
      throwsFormatException,
    );
  });
}
