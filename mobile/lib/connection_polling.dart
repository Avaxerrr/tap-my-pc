import 'dart:async';

import 'connection.dart';
import 'selected_connection.dart';

typedef PcStatusReading = ({
  PcApi client,
  Map<String, dynamic> status,
  PcProfile? recoveredProfile,
});

typedef PcDeviceLists = ({
  List<dynamic> outputs,
  List<dynamic> monitors,
  List<dynamic> shortcuts,
  Map<String, String> errors,
});

/// Owns the polling cadence and the API connection that commands can use.
class PcConnectionPolling {
  final PcApi Function(PcProfile) createApi;
  PcApi? _api;
  Timer? _timer;
  int _ticks = 0;
  bool _refreshing = false;

  PcConnectionPolling({required this.createApi});

  PcApi? get api => _api;
  bool get isRefreshing => _refreshing;

  void start(void Function(bool retryTick) onTick) {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      onTick(++_ticks % 5 == 0);
    });
  }

  Future<void> refresh(
    PcProfile profile,
    Iterable<String> addresses, {
    required bool Function() isCurrent,
    required bool Function() canAdoptConnection,
    required void Function() onReconnecting,
    required Future<bool> Function(PcStatusReading reading) onStatus,
    required void Function(PcDeviceLists lists) onDevices,
    required void Function(Object error) onFailure,
  }) async {
    final client = _api;
    _refreshing = true;
    try {
      Map<String, dynamic> status;
      VerifiedPcConnection? recovered;
      final preferNetwork =
          profile.connectionMode == 'auto' &&
          _ticks % 5 == 0 &&
          client != null &&
          client.transportLabel != 'Local network';
      if (client == null || preferNetwork) {
        recovered = await connectSelectedPc(
          profile,
          addresses,
          wifi: createApi,
          activeApi: client,
        );
        status = recovered.status;
      } else {
        try {
          status = Map<String, dynamic>.from(await client.request('/status'));
        } catch (error) {
          if (!isCurrent()) return;
          disconnect();
          if (error is PcApiException && error.statusCode == 401) rethrow;
          onReconnecting();
          recovered = await connectSelectedPc(
            profile,
            addresses,
            wifi: createApi,
            excludedAddresses: client.isBluetooth
                ? {}
                : {client.profile.address},
          );
          status = recovered.status;
        }
      }

      if (recovered != null) {
        if (!isCurrent() || !canAdoptConnection()) {
          if (!identical(recovered.api, _api)) recovered.api.close();
          return;
        }
        if (!identical(_api, recovered.api)) _api?.close();
        _api = recovered.api;
      }

      if (!isCurrent()) return;
      final active = _api!;
      final loadDevices = await onStatus((
        client: active,
        status: status,
        recoveredProfile: recovered?.profile,
      ));
      if (loadDevices) {
        final lists = await _loadDevices(active);
        if (isCurrent()) onDevices(lists);
      }
    } catch (error) {
      if (isCurrent()) {
        disconnect();
        onFailure(error);
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<PcDeviceLists> _loadDevices(PcApi client) async {
    final errors = <String, String>{};
    Future<List<dynamic>> load(String path, String label) async {
      try {
        return await client.request(path) as List<dynamic>;
      } catch (error) {
        // A revoked credential invalidates connectivity, even on an optional read.
        if (error is PcApiException && error.statusCode == 401) rethrow;
        final detail = error is PcApiException
            ? ' (HTTP ${error.statusCode})'
            : '';
        errors[path] = '$label could not be loaded$detail. Pull to refresh.';
        return [];
      }
    }

    final lists = await Future.wait([
      load('/audio/outputs', 'Audio outputs'),
      load('/monitors', 'Individual display controls'),
      load('/shortcuts', 'Shortcuts'),
    ]);
    return (
      outputs: lists[0],
      monitors: lists[1],
      shortcuts: lists[2],
      errors: errors,
    );
  }

  Future<void> probe(
    PcProfile profile,
    Iterable<String> addresses,
    Future<void> Function(VerifiedPcConnection) onVerified,
  ) async {
    final connection = await connectSelectedPc(profile, addresses);
    try {
      await onVerified(connection);
    } finally {
      connection.api.close();
    }
  }

  void disconnect() {
    _api?.close();
    _api = null;
  }

  void dispose() {
    _timer?.cancel();
    disconnect();
  }
}
