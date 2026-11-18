import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String normalizePin(String value) =>
    value.replaceAll(RegExp(r'[:\s-]'), '').toLowerCase();

class PcProfile {
  final String name, address, pin, token;
  const PcProfile(this.name, this.address, this.pin, this.token);
  PcProfile atAddress(String next) => PcProfile(name, next, pin, token);
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'pin': pin,
    'token': token,
  };
  factory PcProfile.fromJson(Map<String, dynamic> j) =>
      PcProfile(j['name'], j['address'], j['pin'], j['token']);
}

class ProfileStore {
  final FlutterSecureStorage storage;
  const ProfileStore([this.storage = const FlutterSecureStorage()]);
  Future<String?> lastSelected() => storage.read(key: 'tapmypc.selected.v1');
  Future<void> select(String pin) =>
      storage.write(key: 'tapmypc.selected.v1', value: normalizePin(pin));
  Future<List<PcProfile>> load() async {
    final value = await storage.read(key: 'tapmypc.profiles.v1');
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((j) => PcProfile.fromJson(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<void> save(List<PcProfile> profiles) => storage.write(
    key: 'tapmypc.profiles.v1',
    value: jsonEncode(profiles.map((p) => p.toJson()).toList()),
  );
}

class PcApi {
  final PcProfile profile;
  late final HttpClient _client;
  PcApi(this.profile) {
    final base = Uri.parse(profile.address);
    if (base.scheme != 'https' ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        (base.path.isNotEmpty && base.path != '/') ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException(
        'Use an HTTPS PC address, with no path or credentials.',
      );
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(normalizePin(profile.pin))) {
      throw const FormatException(
        'Copy the SHA-256 certificate fingerprint from Advanced settings on the PC.',
      );
    }
    _client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = const Duration(seconds: 8);
    // Verify the exact leaf certificate before returning a socket to HTTP.
    // No pairing code, bearer credential, or HTTP request is sent beforehand.
    _client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (uri.host != base.host || uri.port != base.port) {
        throw const HandshakeException('Unexpected PC endpoint.');
      }
      final pending =
          SecureSocket.connect(
            uri.host,
            uri.port,
            context: SecurityContext(withTrustedRoots: false),
            onBadCertificate: (cert) =>
                normalizePin(profile.pin) ==
                sha256.convert(cert.der).toString(),
            timeout: const Duration(seconds: 8),
          ).then<Socket>((socket) {
            final cert = socket.peerCertificate;
            if (cert == null ||
                sha256.convert(cert.der).toString() !=
                    normalizePin(profile.pin) ||
                DateTime.now().isBefore(cert.startValidity) ||
                DateTime.now().isAfter(cert.endValidity)) {
              socket.destroy();
              throw const HandshakeException(
                'PC identity does not match. Verify its fingerprint locally.',
              );
            }
            return socket;
          });
      return ConnectionTask.fromSocket(pending, () {
        pending.then((s) => s.destroy(), onError: (Object _) {});
      });
    };
  }
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final uri = Uri.parse(profile.address).resolve('/api/v1$path');
    final req = await _client
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 8));
    req.followRedirects = false;
    if (profile.token.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${profile.token}');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close().timeout(const Duration(seconds: 8));
    final text = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 8));
    dynamic result;
    try {
      result = jsonDecode(text);
    } catch (_) {
      result = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PcApiException(
        response.statusCode,
        result is Map
            ? result['error'] ?? 'Request failed (${response.statusCode}).'
            : 'Request failed.',
      );
    }
    return result;
  }

  void close() => _client.close(force: true);
}

class PcApiException extends HttpException {
  final int statusCode;
  PcApiException(this.statusCode, super.message);
}

String? discoveredAddress(PcProfile profile, Map<dynamic, dynamic> event) {
  if (event['kind'] != 'found' ||
      event['fingerprint'] is! String ||
      normalizePin(event['fingerprint']) != normalizePin(profile.pin) ||
      event['address'] is! String) {
    return null;
  }
  final uri = Uri.tryParse(event['address']);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.port < 1024 ||
      uri.port > 65535) {
    return null;
  }
  final ip = InternetAddress.tryParse(uri.host);
  if (ip == null || ip.type != InternetAddressType.IPv4) return null;
  final bytes = ip.rawAddress;
  final local =
      ip.isLoopback ||
      bytes[0] == 10 ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31);
  return local ? uri.origin : null;
}

class VerifiedPcConnection {
  final PcProfile profile;
  final PcApi api;
  final Map<String, dynamic> status;
  VerifiedPcConnection(this.profile, this.api, this.status);
}

/// Untrusted discovery only provides candidates. TLS identity verification in
/// PcApi runs before the saved bearer credential is sent to any candidate.
Future<VerifiedPcConnection> reconnectPc(
  PcProfile profile,
  Iterable<String> addresses,
) async {
  Object lastError = const SocketException('No reachable address found.');
  for (final address in addresses.toSet().take(5)) {
    PcApi? client;
    try {
      final candidate = profile.atAddress(address);
      client = PcApi(candidate);
      final response = Map<String, dynamic>.from(
        await client.request('/status'),
      );
      return VerifiedPcConnection(candidate, client, response);
    } catch (error) {
      client?.close();
      if (error is PcApiException && error.statusCode == 401) rethrow;
      lastError = error;
    }
  }
  throw lastError;
}
