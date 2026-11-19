import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'certificate_identity.dart';
import 'phone_identity.dart';
import 'wake_on_lan.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String normalizePin(String value) =>
    value.replaceAll(RegExp(r'[:\s-]'), '').toLowerCase();

/// Direct IP endpoints match the desktop listener's strict Host validation.
String networkAddress(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      InternetAddress.tryParse(uri.host)?.type != InternetAddressType.IPv4 ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.port < 1024 ||
      uri.port > 65535) {
    throw const FormatException(
      'Copy the full HTTPS IPv4 address and port shown on the PC, for example https://100.80.90.100:45831.',
    );
  }
  return uri.origin;
}

bool isTailscaleAddress(String address) {
  final ip = InternetAddress.tryParse(Uri.tryParse(address)?.host ?? '');
  final bytes = ip?.rawAddress;
  return bytes != null &&
      bytes.length == 4 &&
      bytes[0] == 100 &&
      bytes[1] >= 64 &&
      bytes[1] <= 127;
}

String connectionModeLabel(String mode) => switch (mode) {
  'local' || 'wifi' => 'Local network only',
  'tailscale' => 'Tailscale only',
  'bluetooth' => 'Bluetooth only',
  _ => 'Automatic',
};

/// Keep the active endpoint separate from the saved addresses for each route.
class PcProfile {
  final String name, address, pin, token;
  final String? keyPin, bluetoothAddress, localAddress, tailscaleAddress;
  final String connectionMode;
  final WakeOnLanSettings? wakeOnLan, automaticWakeOnLan;
  WakeOnLanSettings? get effectiveWakeOnLan => wakeOnLan ?? automaticWakeOnLan;
  const PcProfile(
    this.name,
    this.address,
    this.pin,
    this.token, {
    this.keyPin,
    this.bluetoothAddress,
    this.localAddress,
    this.tailscaleAddress,
    this.connectionMode = 'auto',
    this.wakeOnLan,
    this.automaticWakeOnLan,
  });
  String? get localEndpoint =>
      localAddress ?? (isTailscaleAddress(address) ? null : address);
  String? get tailscaleEndpoint =>
      tailscaleAddress ?? (isTailscaleAddress(address) ? address : null);

  PcProfile copy({
    String? address,
    String? token,
    String? keyPin,
    String? bluetoothAddress,
    String? localAddress,
    String? tailscaleAddress,
    String? connectionMode,
    WakeOnLanSettings? wakeOnLan,
    bool clearWakeOnLan = false,
    WakeOnLanSettings? automaticWakeOnLan,
  }) => PcProfile(
    name,
    address ?? this.address,
    pin,
    token ?? this.token,
    keyPin: keyPin ?? this.keyPin,
    bluetoothAddress: bluetoothAddress ?? this.bluetoothAddress,
    localAddress: localAddress ?? localEndpoint,
    tailscaleAddress: tailscaleAddress ?? tailscaleEndpoint,
    connectionMode: connectionMode ?? this.connectionMode,
    wakeOnLan: clearWakeOnLan ? null : wakeOnLan ?? this.wakeOnLan,
    automaticWakeOnLan: automaticWakeOnLan ?? this.automaticWakeOnLan,
  );
  PcProfile atAddress(String next) => copy(
    address: next,
    localAddress: isTailscaleAddress(next) ? null : next,
    tailscaleAddress: isTailscaleAddress(next) ? next : null,
  );
  PcProfile withKeyPin(String key) => copy(keyPin: key);
  PcProfile withToken(String credential) => copy(token: credential);
  PcProfile withConnectionMode(String mode) => copy(connectionMode: mode);
  PcProfile withBluetoothAddress(String address) =>
      copy(bluetoothAddress: address);
  PcProfile withWakeOnLan(WakeOnLanSettings? settings) =>
      copy(wakeOnLan: settings, clearWakeOnLan: settings == null);

  PcProfile withAutomaticWakeHint(Object? network) => network is Map
      ? copy(
          automaticWakeOnLan: WakeOnLanSettings.fromJson(network['wakeOnLan']),
        )
      : this;

  PcProfile withNetworkHints(dynamic value) {
    if (value is! Map) return this;
    var updated = this;
    for (final key in ['localAddress', 'tailscaleAddress']) {
      final raw = value[key];
      if (raw is! String) continue;
      try {
        final endpoint = networkAddress(raw);
        final ip = InternetAddress(endpointHost(endpoint));
        final bytes = ip.rawAddress;
        final local =
            ip.isLoopback ||
            bytes[0] == 10 ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31);
        if (key == 'tailscaleAddress' && isTailscaleAddress(endpoint)) {
          updated = updated.copy(tailscaleAddress: endpoint);
        } else if (key == 'localAddress' && local) {
          updated = updated.copy(localAddress: endpoint);
        }
      } on FormatException {
        /* Invalid optional hints never invalidate control. */
      }
    }
    return updated;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'pin': pin,
    'token': token,
    if (keyPin != null) 'keyPin': keyPin,
    if (bluetoothAddress != null) 'bluetoothAddress': bluetoothAddress,
    if (localEndpoint != null) 'localAddress': localEndpoint,
    if (tailscaleEndpoint != null) 'tailscaleAddress': tailscaleEndpoint,
    if (connectionMode != 'auto') 'connectionMode': connectionMode,
    if (wakeOnLan != null) 'wakeOnLan': wakeOnLan!.toJson(),
    if (automaticWakeOnLan != null)
      'automaticWakeOnLan': automaticWakeOnLan!.toJson(),
  };
  factory PcProfile.fromJson(Map<String, dynamic> j) {
    var mode = j['connectionMode'] ?? 'auto';
    if (mode == 'wifi') {
      mode = isTailscaleAddress(j['address']) ? 'tailscale' : 'local';
    }
    return PcProfile(
      j['name'],
      j['address'],
      j['pin'],
      j['token'],
      keyPin: j['keyPin'],
      bluetoothAddress: j['bluetoothAddress'],
      localAddress: j['localAddress'],
      tailscaleAddress: j['tailscaleAddress'],
      connectionMode: mode,
      wakeOnLan: WakeOnLanSettings.fromJson(j['wakeOnLan']),
      automaticWakeOnLan: WakeOnLanSettings.fromJson(j['automaticWakeOnLan']),
    );
  }
}

String endpointHost(String address) => Uri.parse(address).host;

/// IP entry uses the PC's already known port; full links are accepted for convenience.
String configuredNetworkAddress(
  String input,
  PcProfile profile, {
  required bool tailscale,
  String? port,
}) {
  final raw = input.trim();
  final saved = tailscale ? profile.tailscaleEndpoint : profile.localEndpoint;
  final number = port == null
      ? Uri.parse(saved ?? profile.address).port
      : int.tryParse(port);
  if (number == null || number < 1024 || number > 65535) {
    throw const FormatException(
      'Use the same TapMyPC port as the PC (1024–65535).',
    );
  }
  final endpoint = networkAddress(
    raw.contains('://') ? raw : 'https://$raw:$number',
  );
  if (isTailscaleAddress(endpoint) != tailscale) {
    throw FormatException(
      tailscale
          ? 'Enter the PC Tailscale IPv4 address (100.64–100.127.x.x).'
          : 'Use the local network address here; Tailscale has a separate address.',
    );
  }
  return endpoint;
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
  String get transportLabel =>
      isTailscaleAddress(profile.address) ? 'Tailscale' : 'Local network';
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
    _initialize('https://127.0.0.1:$port', tunnel: true);
    // A peer/channel carries one RFCOMM stream; queue optional HTTP requests on it.
    _client.maxConnectionsPerHost = 1;
  }
  void _initialize(String address, {bool tunnel = false}) {
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
    final connectTimeout = tunnel || isTailscaleAddress(address)
        ? _timeout
        : const Duration(seconds: 3);
    _client = HttpClient(context: SecurityContext(withTrustedRoots: false))
      ..connectionTimeout = connectTimeout;
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
            timeout: connectTimeout,
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
