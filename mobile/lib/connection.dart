import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'certificate_identity.dart';
import 'phone_identity.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String normalizePin(String value) =>
    value.replaceAll(RegExp(r'[:\s-]'), '').toLowerCase();

class PcProfile {
  final String name, address, pin, token;
  final String? keyPin, bluetoothAddress;
  final String connectionMode;
  const PcProfile(
    this.name,
    this.address,
    this.pin,
    this.token, {
    this.keyPin,
    this.bluetoothAddress,
    this.connectionMode = 'auto',
  });
  PcProfile atAddress(String next) => PcProfile(
    name,
    next,
    pin,
    token,
    keyPin: keyPin,
    bluetoothAddress: bluetoothAddress,
    connectionMode: connectionMode,
  );
  PcProfile withKeyPin(String key) => PcProfile(
    name,
    address,
    pin,
    token,
    keyPin: key,
    bluetoothAddress: bluetoothAddress,
    connectionMode: connectionMode,
  );
  PcProfile withToken(String credential) => PcProfile(
    name,
    address,
    pin,
    credential,
    keyPin: keyPin,
    bluetoothAddress: bluetoothAddress,
    connectionMode: connectionMode,
  );
  PcProfile withConnectionMode(String mode) => PcProfile(
    name,
    address,
    pin,
    token,
    keyPin: keyPin,
    bluetoothAddress: bluetoothAddress,
    connectionMode: mode,
  );
  PcProfile withBluetoothAddress(String address) => PcProfile(
    name,
    this.address,
    pin,
    token,
    keyPin: keyPin,
    bluetoothAddress: address,
    connectionMode: connectionMode,
  );
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'pin': pin,
    'token': token,
    if (keyPin != null) 'keyPin': keyPin,
    if (bluetoothAddress != null) 'bluetoothAddress': bluetoothAddress,
    if (connectionMode != 'auto') 'connectionMode': connectionMode,
  };
  factory PcProfile.fromJson(Map<String, dynamic> j) => PcProfile(
    j['name'],
    j['address'],
    j['pin'],
    j['token'],
    keyPin: j['keyPin'],
    bluetoothAddress: j['bluetoothAddress'],
    connectionMode: j['connectionMode'] ?? 'auto',
  );
}

/// Re-enrollment replaces only the deliberately selected profile and duplicate trusted identity.
List<PcProfile> replacePcProfile(
  List<PcProfile> profiles,
  PcProfile result, {
  PcProfile? recovering,
}) => [
  ...profiles.where(
    (p) =>
        p.pin != recovering?.pin &&
        p.pin != result.pin &&
        !(result.keyPin != null && p.keyPin == result.keyPin),
  ),
  result,
];

class ProfileStore {
  static Future<void> _writes = Future<void>.value();
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

  Future<void> save(List<PcProfile> profiles) {
    final value = jsonEncode(profiles.map((p) => p.toJson()).toList());
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => storage.write(key: 'tapmypc.profiles.v1', value: value));
  }
}

class PcApi {
  final PcProfile profile;
  late final HttpClient _client;
  late final String _requestAddress;
  Duration _timeout = const Duration(seconds: 8);
  String get transportLabel => 'Wi-Fi';
  bool get isBluetooth => false;
  String? _verifiedKeyPin;
  PcProfile get verifiedProfile =>
      _verifiedKeyPin == null ? profile : profile.withKeyPin(_verifiedKeyPin!);
  PcApi(this.profile) {
    _initialize(profile.address);
  }
  PcApi.tunnel(this.profile, int port) {
    if (port < 1 || port > 65535) {
      throw const FormatException('Invalid Bluetooth tunnel port.');
    }
    _timeout = const Duration(seconds: 25);
    _initialize('https://127.0.0.1:$port');
    // A peer/channel carries one RFCOMM stream; queue optional HTTP requests on it.
    _client.maxConnectionsPerHost = 1;
  }
  void _initialize(String address) {
    _requestAddress = address;
    final base = Uri.parse(address);
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
    if (profile.keyPin != null &&
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(profile.keyPin!)) {
      throw const FormatException(
        'The saved PC identity key is invalid. Pair again.',
      );
    }
    _client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = _timeout;
    // Verify enrolled leaf or previously verified identity key before HTTP sees the socket.
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
            onBadCertificate: (cert) => acceptsCertificate(
              cert,
              normalizePin(profile.pin),
              profile.keyPin,
            ),
            timeout: _timeout,
          ).then<Socket>((socket) {
            final cert = socket.peerCertificate;
            if (cert == null ||
                !acceptsCertificate(
                  cert,
                  normalizePin(profile.pin),
                  profile.keyPin,
                )) {
              socket.destroy();
              throw const HandshakeException(
                'PC identity changed or its certificate is invalid. Check the PC clock; after a local identity reset, use Re-pair selected PC and scan its new QR.',
              );
            }
            _verifiedKeyPin = certificateKeyPin(cert.der);
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
    final uri = Uri.parse(_requestAddress).resolve('/api/v1$path');
    final req = await _client.openUrl(method, uri).timeout(_timeout);
    req.followRedirects = false;
    if (profile.token.isNotEmpty) {
      req.headers.set('Authorization', 'Bearer ${profile.token}');
      final name = await PhoneIdentity.name();
      if (name != null) {
        req.headers.set(
          'X-TapMyPC-Device-Name',
          base64Encode(utf8.encode(name)),
        );
      }
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close().timeout(_timeout);
    final text = await utf8.decoder.bind(response).join().timeout(_timeout);
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
      !(normalizePin(event['fingerprint']) == normalizePin(profile.pin) ||
          (profile.keyPin != null &&
              event['keyFingerprint'] == profile.keyPin)) ||
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
  Iterable<String> addresses, {
  PcApi Function(PcProfile) createApi = PcApi.new,
}) async {
  Object lastError = const SocketException('No reachable address found.');
  for (final address in addresses.toSet().take(5)) {
    PcApi? client;
    try {
      final candidate = profile.atAddress(address);
      client = createApi(candidate);
      final response = Map<String, dynamic>.from(
        await client.request('/status'),
      );
      return VerifiedPcConnection(client.verifiedProfile, client, response);
    } catch (error) {
      client?.close();
      if (error is PcApiException && error.statusCode == 401) rethrow;
      lastError = error;
    }
  }
  throw lastError;
}
