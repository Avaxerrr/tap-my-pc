import 'dart:io';
import 'connection.dart';
import 'bluetooth_connection.dart';

List<String> selectedNetworkAddresses(
  PcProfile profile,
  Iterable<String> addresses, {
  Set<String> excludedAddresses = const {},
}) {
  final local = {
    if (profile.localEndpoint != null) profile.localEndpoint!,
    ...addresses.where((a) => !isTailscaleAddress(a)),
  }.where((a) => !excludedAddresses.contains(a)).take(3);
  final tail = [
    if (profile.tailscaleEndpoint != null) profile.tailscaleEndpoint!,
  ].where((a) => !excludedAddresses.contains(a));
  return switch (profile.connectionMode) {
    'local' || 'wifi' => local.toList(),
    'tailscale' => tail.toList(),
    'bluetooth' => [],
    _ => [...local, ...tail],
  };
}

Future<VerifiedPcConnection> connectSelectedPc(
  PcProfile profile,
  Iterable<String> addresses, {
  PcApi Function(PcProfile) wifi = PcApi.new,
  PcApi Function(PcProfile) bluetooth = BluetoothPcApi.new,
  PcApi? activeApi,
  Set<String> excludedAddresses = const {},
}) async {
  final mode = profile.connectionMode;
  final network = selectedNetworkAddresses(
    profile,
    addresses,
    excludedAddresses: excludedAddresses,
  );
  Object? failure;
  if (mode != 'bluetooth') {
    try {
      return await reconnectPc(profile, network, createApi: wifi);
    } catch (error) {
      if (error is PcApiException && error.statusCode == 401) rethrow;
      failure = error;
      if (mode != 'auto') {
        if (network.isEmpty) {
          throw FormatException(
            mode == 'tailscale'
                ? 'Set up the Tailscale address in Connection settings.'
                : 'Set up a local address or connect to the PC local network.',
          );
        }
        rethrow;
      }
    }
  }
  if (profile.bluetoothAddress == null) {
    if (failure != null) throw failure;
    throw const FormatException(
      'Connect over a network once to learn this PC’s Bluetooth connection.',
    );
  }
  // Reuse a healthy active RFCOMM stream when only probing for a better network route.
  final client = activeApi?.isBluetooth == true
      ? activeApi!
      : bluetooth(profile);
  try {
    final status = Map<String, dynamic>.from(await client.request('/status'));
    return VerifiedPcConnection(client.verifiedProfile, client, status);
  } catch (error) {
    client.close();
    if (error is PcApiException && error.statusCode == 401) rethrow;
    if (failure != null) {
      throw const SocketException(
        'Local network, Tailscale and Bluetooth are unavailable. Check the PC and Connection settings.',
      );
    }
    rethrow;
  }
}
