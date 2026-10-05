import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/server_host.dart';

void main() {
  test('the server restarts by itself after it dies, with the same data', () async {
    final dir = await Directory.systemTemp.createTemp('host_test');
    var port = await ServerHost.start(dir.path, port: 0);
    var api = ApiClient('http://127.0.0.1:$port');
    await api.post('/api/setup', {'shopName': 'تجربة', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123'});
    api.close();

    // السيرفر وقع فجأة
    ServerHost.debugKill();
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (ServerHost.restarts == 0 && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(ServerHost.restarts, 1);

    // رجع لوحده، والبيانات زي ما هي
    port = await ServerHost.start(dir.path, port: 0);
    api = ApiClient('http://127.0.0.1:$port');
    final info = await api.get('/api/info');
    expect(info['setupDone'], true);
    expect(info['shopName'], 'تجربة');
    api.close();
    final log = File('${dir.path}/logs/server.log').readAsStringSync();
    expect(log, contains('السيرفر وقف فجأة'));
    expect(log, contains('السيرفر رجع اشتغل'));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
