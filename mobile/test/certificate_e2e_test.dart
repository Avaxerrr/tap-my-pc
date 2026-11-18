import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import '../test_support/certificate_scenario.dart';

void main() {
  const fixturePath = String.fromEnvironment('TEST_CERT_FIXTURE_PATH');
  test(
    'Production Windows API and Flutter certificate lifecycle end to end',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final fixture = Map<String, dynamic>.from(
        jsonDecode(File(fixturePath).readAsStringSync()),
      );
      await runCertificateScenario(fixture);
    },
    skip: fixturePath.isEmpty
        ? 'Run with the isolated CertificateTestHost fixture.'
        : false,
  );
}
