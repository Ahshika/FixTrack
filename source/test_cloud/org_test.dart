// تجربة حقيقية لربط فرعين عن طريق Firebase (بتعمل بيانات تجريبية وتمسحها).
// التشغيل: flutter test test_cloud/org_test.dart
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(FixTrackServer, ApiClient, Directory)> _branch(String branchName) async {
  final dir = await Directory.systemTemp.createTemp('fixtrack_org');
  final server = FixTrackServer(dataDir: dir.path, requestedPort: 0);
  await server.start();
  final api = ApiClient('http://127.0.0.1:${server.port}');
  api.token = (await api.post('/api/setup', {
    'shopName': 'محل تجربة الفروع', 'branchName': branchName, 'ownerName': 'تجربة', 'username': 'owner', 'password': 'owner123',
  }))['token'] as String;
  // تسجيل حساب Firebase للفرع
  await server.syncNow();
  return (server, api, dir);
}

void main() {
  test('two branches link, share summaries and stock, and transfer goods', () async {
    final (s1, a1, d1) = await _branch('فرع المعادي');
    final (s2, a2, d2) = await _branch('فرع مدينة نصر');
    String? transferId;
    try {
      // فرع 1 عنده بضاعة ومبيعات
      final cover = (await a1.post('/api/products', {'name': 'جراب تجربة الفروع', 'barcode': '2099999999994', 'costCents': 3000, 'priceCents': 7500, 'qty': 10}))['product'] as Map;
      await a1.post('/api/sales', {'items': [{'productId': cover['id'], 'qty': 2}], 'payments': [{'method': 'cash', 'amountCents': 15000}]});

      // فرع 1 يعمل مجموعة ويطلع كود؛ فرع 2 يدخل الكود
      final org = await a1.post('/api/org/create', {'name': 'محل تجربة'});
      expect(org['linked'], true);
      expect(org['isOrgOwner'], true);
      final code = (await a1.post('/api/org/invite'))['code'] as String;
      try {
        await a2.post('/api/org/join', {'code': 'WRONGCOD'});
        fail('wrong code should fail');
      } on ApiException catch (e) {
        expect(e.status, 404);
      }
      final joined = await a2.post('/api/org/join', {'code': code});
      expect((joined['members'] as List).length, 2);

      // ملخص الفرعين عند صاحب المحل
      final summary = await a1.get('/api/org/summary');
      final b1 = (summary['branches'] as List).singleWhere((b) => b['branchName'] == 'فرع المعادي');
      expect(b1['salesCents'], 15000);

      // فرع 2 يدوّر على الصنف في الفروع التانية
      final stock = await a2.get('/api/org/stock', query: {'q': 'جراب تجربة'});
      expect((stock['results'] as List).single['qty'], 8);

      // فرع 1 يحوّل 3 جرابات لفرع 2
      final uid2 = ((joined['members'] as List).singleWhere((m) => m['isMe'] == true))['uid'];
      transferId = (await a1.post('/api/org/transfers', {'toUid': uid2, 'items': [{'productId': cover['id'], 'qty': 3}]}))['id'] as String;
      expect(((await a1.get('/api/products', query: {'q': 'جراب تجربة'}))['products'] as List).single['qty'], 5);

      final incoming = (await a2.get('/api/org/transfers'))['incoming'] as List;
      expect(incoming.single['id'], transferId);
      await a2.post('/api/org/transfers/$transferId/receive');
      final p2 = await a2.get('/api/products/lookup', query: {'barcode': '2099999999994'});
      expect(p2['product']['qty'], 3);
      expect(p2['product']['priceCents'], 7500);
      expect((await a2.get('/api/org/transfers'))['incoming'], isEmpty);
    } finally {
      // تنضيف: فرع 2 يخرج، وفرع 1 (صاحب المجموعة) يمسح كل حاجة
      try {
        await a2.post('/api/org/leave');
      } catch (_) {}
      await s1.cleanupOrgForTests(transferId);
      for (final (s, a, d) in [(s1, a1, d1), (s2, a2, d2)]) {
        await s.cleanupCloudForTests();
        a.close();
        await s.stop();
        await d.delete(recursive: true);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
