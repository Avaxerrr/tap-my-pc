import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'connection.dart';
import 'selected_connection.dart';

const homeScreenChannel = MethodChannel('dev.tapmypc/home_screen');
const _background = MethodChannel('dev.tapmypc/home_background');

// Launcher metadata carries no endpoint, certificate pin, or credential.
String homeProfileId(PcProfile profile) => sha256
    .convert(utf8.encode('tapmypc-home:${normalizePin(profile.pin)}'))
    .toString();

Future<void> publishHomeShortcuts(PcProfile? profile) async {
  try {
    await homeScreenChannel.invokeMethod<void>(
      'publish',
      profile == null
          ? null
          : {
              'id': homeProfileId(profile),
              'name': profile.name,
              'wake': profile.effectiveWakeOnLan != null,
            },
    );
  } on MissingPluginException {
    // Android owns the launcher integration.
  } on PlatformException {
    // The dashboard remains usable when the launcher rejects publication.
  }
}

Future<void> runHomeAction(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  Map<String, Object?> result;
  try {
    result = await executeHomeAction(arguments);
  } catch (_) {
    result = {
      'message': 'Could not read the saved PC. Open TapMyPC and try again.',
    };
  }
  await _background.invokeMethod<void>('complete', result);
}

Future<Map<String, Object?>> executeHomeAction(
  List<String> arguments, {
  ProfileStore store = const ProfileStore(),
  PcApi Function(PcProfile) createApi = PcApi.new,
}) async {
  final action = arguments.firstOrNull;
  final profiles = await store.load();
  if (action == 'profiles') {
    return {
      'profiles': [
        for (final profile in profiles)
          {'id': homeProfileId(profile), 'name': profile.name},
      ],
    };
  }
  final targetId = arguments.length > 1 ? arguments[1] : null;
  final profile = profiles
      .where((p) => homeProfileId(p) == targetId)
      .firstOrNull;
  if (profile == null) return {'message': 'PC no longer paired. Open TapMyPC.'};

  String message;
  if (action == 'wake') {
    final settings = profile.effectiveWakeOnLan;
    if (settings == null) {
      message = 'Set up Wake-on-LAN in TapMyPC.';
    } else {
      try {
        await settings.send();
        message = 'Wake packet sent';
      } on PlatformException catch (error) {
        message = error.message ?? 'Could not send the wake packet.';
      }
    }
  } else if (action == 'refresh') {
    message = await _checkStatus(profile, createApi);
  } else {
    message = 'Unknown home-screen action';
  }
  return {'name': profile.name, 'message': message};
}

Future<String> _checkStatus(
  PcProfile profile,
  PcApi Function(PcProfile) createApi,
) async {
  final saved = selectedNetworkAddresses(profile, const []).toSet();
  if (saved.isEmpty) {
    return profile.connectionMode == 'bluetooth'
        ? 'Open TapMyPC to check Bluetooth.'
        : 'No saved network address';
  }
  for (final address in saved) {
    PcApi? client;
    try {
      client = createApi(profile.atAddress(address));
      await client.request('/status').timeout(const Duration(seconds: 3));
      return 'Online · ${client.transportLabel}';
    } on PcApiException catch (error) {
      if (error.statusCode == 401) return 'Pairing required';
    } catch (_) {
      // Try the next saved network route for this same PC.
    } finally {
      client?.close();
    }
  }
  return 'PC unavailable';
}
