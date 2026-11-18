import 'dart:io';
import 'connection.dart';
import 'bluetooth_connection.dart';

Future<VerifiedPcConnection> connectSelectedPc(
  PcProfile profile,
  Iterable<String> addresses, {
  PcApi Function(PcProfile) wifi = PcApi.new,
  PcApi Function(PcProfile) bluetooth = BluetoothPcApi.new,
}) async {
  Object? wifiFailure;
  if (profile.connectionMode != 'bluetooth') {
    try {
      return await reconnectPc(profile, addresses, createApi: wifi);
    } catch (error) {
      if (error is PcApiException && error.statusCode == 401) rethrow;
      if (profile.connectionMode == 'wifi' ||
          profile.bluetoothAddress == null) {
        rethrow;
      }
      wifiFailure = error;
    }
  }
  final client = bluetooth(profile);
  try {
    final status = Map<String, dynamic>.from(await client.request('/status'));
    return VerifiedPcConnection(client.verifiedProfile, client, status);
  } catch (error) {
    client.close();
    if (error is PcApiException && error.statusCode == 401) rethrow;
    if (wifiFailure != null) {
      throw const SocketException(
        'Wi-Fi and Bluetooth are unavailable. Check the PC, Bluetooth power, Nearby devices permission, and pairing in Connection settings.',
      );
    }
    rethrow;
  }
}
