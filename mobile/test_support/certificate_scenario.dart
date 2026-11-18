import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/pairing_invitation.dart';

/// Runs against the isolated, loopback-only .NET CertificateTestHost.
Future<PcProfile> runCertificateScenario(Map<String, dynamic> fixture) async {
  final control = HttpClient();
  Future<Map<String, dynamic>> step(String action) async {
    final request = await control.postUrl(
      Uri.parse('${fixture['controlUrl']}/test/$action'),
    );
    request.headers.set('X-Test-Key', fixture['controlKey'] as String);
    final response = await request.close();
    expect(response.statusCode, 200);
    return Map<String, dynamic>.from(
      jsonDecode(await utf8.decoder.bind(response).join()),
    );
  }

  Future<void> connected(PcProfile profile) async {
    final api = PcApi(profile);
    try {
      expect((await api.request('/status'))['pcName'], isNotEmpty);
    } finally {
      api.close();
    }
  }

  Future<void> rejected(PcProfile profile) async {
    final api = PcApi(profile);
    try {
      await expectLater(api.request('/status'), throwsA(anything));
    } finally {
      api.close();
    }
  }

  const store = ProfileStore();
  try {
    final initial = Map<String, dynamic>.from(fixture['state']);
    final paired = await PairingInvitation.parse(
      initial['invitation'],
    ).redeem();
    expect(paired.keyPin, initial['keyPin']);
    final other = PcProfile(
      'Other saved PC',
      'https://192.168.0.240:45831',
      List.filled(64, 'b').join(),
      'unrelated-saved-credential',
    );

    // Exercise a pre-upgrade profile with only the exact leaf fingerprint.
    final legacy = PcProfile(
      paired.name,
      paired.address,
      paired.pin,
      paired.token,
    );
    await store.save([other, legacy]);
    final migration = PcApi((await store.load()).last);
    late PcProfile saved;
    try {
      await migration.request('/status');
      saved = migration.verifiedProfile;
      expect(saved.keyPin, initial['keyPin']);
      await store.save(replacePcProfile(await store.load(), saved));
    } finally {
      migration.close();
    }
    await store.select(saved.pin);

    final renewed = await step('renew');
    expect(renewed['fingerprint'], isNot(initial['fingerprint']));
    expect(renewed['keyPin'], initial['keyPin']);
    saved = (await store.load()).last;
    await connected(
      saved,
    ); // Original token and saved profile work after renewal.
    await rejected(
      legacy,
    ); // Unmigrated leaf-only profiles never silently trust a new certificate.
    final restarted = await step('restart');
    expect(restarted['fingerprint'], renewed['fingerprint']);
    await connected(saved);

    final expired = await step('expire');
    expect(expired['fingerprint'], isNot(renewed['fingerprint']));
    expect(expired['keyPin'], initial['keyPin']);
    await connected(
      saved,
    ); // An offline PC can renew after expiry using the same key.

    expect((await step('lose'))['recoveryRequired'], true);
    await rejected(saved);
    final replacement = await step('reset');
    expect(replacement['keyPin'], isNot(initial['keyPin']));
    await rejected(saved);
    final staleToken = PcApi(
      PcProfile(
        saved.name,
        saved.address,
        replacement['fingerprint'],
        saved.token,
      ),
    );
    try {
      await expectLater(
        staleToken.request('/status'),
        throwsA(
          isA<PcApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    } finally {
      staleToken.close();
    }

    final invitation = PairingInvitation.parse(replacement['invitation']);
    final recovered = await invitation.redeem();
    expect(recovered.token, isNot(saved.token));
    await expectLater(invitation.redeem(), throwsA(isA<PcApiException>()));
    await store.save(
      replacePcProfile(await store.load(), recovered, recovering: saved),
    );
    await store.select(recovered.pin);
    final profiles = await store.load();
    expect(profiles, hasLength(2));
    expect(profiles.first.toJson(), other.toJson());
    expect(profiles.last.keyPin, replacement['keyPin']);
    expect(await store.lastSelected(), recovered.pin);
    await connected(profiles.last);
    final finalRestart = await step('restart');
    expect(finalRestart['fingerprint'], replacement['fingerprint']);
    await connected((await store.load()).last);
    return recovered;
  } finally {
    control.close(force: true);
  }
}
