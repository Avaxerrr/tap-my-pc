import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapmypc_mobile/connection.dart';
import 'package:tapmypc_mobile/connection_polling.dart';

class PendingStatusApi extends PcApi {
  PendingStatusApi(super.profile);

  final status = Completer<Map<String, dynamic>>();
  bool closed = false;

  @override
  Future<dynamic> request(String path, {String method = 'GET', Object? body}) {
    expect(path, '/status');
    return status.future;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  test(
    'a superseded status poll releases its client before publication',
    () async {
      const profile = PcProfile(
        'First PC',
        'https://192.168.1.10:45831',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'fixture-token',
      );
      final pending = PendingStatusApi(profile);
      final polling = PcConnectionPolling(createApi: (_) => pending);
      addTearDown(polling.dispose);

      var isCurrent = true;
      final refresh = polling.refresh(
        profile,
        const [],
        isCurrent: () => isCurrent,
        canAdoptConnection: () => true,
        onReconnecting: () => fail('Unexpected reconnect'),
        onStatus: (_) async => fail('Superseded status was published'),
        onDevices: (_) => fail('Superseded device lists were published'),
        onFailure: (error) => fail('Unexpected failure: $error'),
      );
      expect(polling.isRefreshing, isTrue);
      isCurrent = false;
      polling.disconnect();
      pending.status.complete({'pcName': profile.name});
      await refresh;

      expect(pending.closed, isTrue);
      expect(polling.api, isNull);
      expect(polling.isRefreshing, isFalse);
    },
  );
}
