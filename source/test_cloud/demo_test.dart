// بيعمل جهاز تجريبي على صفحة التتبع عشان نشوف شكلها، أو يمسحه.
// FIXTRACK_DEMO=create  أو  FIXTRACK_DEMO=cleanup
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mode = Platform.environment['FIXTRACK_DEMO'];
  final dir = Directory('${Directory.systemTemp.path}/fixtrack_demo');

  test('demo $mode', () async {
    if (mode == 'create' && dir.existsSync()) dir.deleteSync(recursive: true);
    final server = FixTrackServer(dataDir: dir.path, requestedPort: 0);
    await server.start();
    final api = ApiClient('http://127.0.0.1:${server.port}');
    try {
      if (mode == 'create') {
        api.token = (await api.post('/api/setup', {
          'shopName': 'محل النور لصيانة الموبايلات', 'shopPhone': '01000000000', 'shopAddress': 'شارع 9، المعادي',
          'branchName': 'فرع المعادي', 'ownerName': 'تجربة', 'username': 'demo', 'password': 'demo1234',
        }))['token'] as String;
        final t = (await api.post('/api/tickets', {
          'customer': {'name': 'أحمد علي', 'phone': '01000000001'},
          'brand': 'Samsung', 'model': 'Galaxy A55', 'problems': ['الشاشة'],
          'estimatedCents': 250000, 'depositCents': 50000,
          'dueAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
        }))['ticket'] as Map<String, dynamic>;
        await api.post('/api/tickets/${t['id']}/status', {'status': 'diagnosing'});
        await api.post('/api/tickets/${t['id']}/approval', {'totalCents': 320000, 'note': 'الشاشة محتاجة تتغير، والفلاتة كمان بايظة'});
        await server.syncNow();
        File('${dir.path}/url.txt').writeAsStringSync('https://fixtrack-7fcf9.web.app/t/${t['publicToken']}');
        // ignore: avoid_print
        print('URL: ${File('${dir.path}/url.txt').readAsStringSync()}  err=${server.cloudError}');
      } else {
        await server.cleanupCloudForTests();
      }
    } finally {
      api.close();
      await server.stop();
      if (mode == 'cleanup') dir.deleteSync(recursive: true);
    }
  });
}
