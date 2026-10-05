// اختبار ضغط: بيملا محل مؤقت بآلاف الأجهزة والفواتير والعملاء، وبيقيس كل طلب بياخد قد إيه.
// التشغيل:  flutter test test_stress/stress_test.dart
// (فولدر مؤقت، عمره ما بيلمس بيانات حقيقية)
import 'dart:async';
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

const _tickets = int.fromEnvironment('TICKETS', defaultValue: 3000);
const _sales = int.fromEnvironment('SALES', defaultValue: 3000);

void main() {
  test('timings with a busy shop', () async {
    final dir = await Directory.systemTemp.createTemp('fixtrack_stress');
    final server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    final api = ApiClient('http://127.0.0.1:${server.port}');
    try {
      api.token = (await api.post('/api/setup', {'shopName': 'محل', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123'}))['token'] as String;
      final sw = Stopwatch()..start();
      final products = <String>[];
      for (var i = 0; i < 300; i++) {
        products.add(((await api.post('/api/products', {'name': 'صنف $i', 'category': 'قسم ${i % 12}', 'costCents': 1000, 'priceCents': 2500, 'qty': 100000, 'lowStock': 2}))['product'] as Map)['id'] as String);
      }
      for (var i = 0; i < _tickets; i++) {
        await api.post('/api/tickets', {
          'customer': {'name': 'عميل ${i % 900}', 'phone': '010${(10000000 + i % 900).toString()}'},
          'brand': i.isEven ? 'Samsung' : 'iPhone', 'model': 'Model ${i % 40}', 'problems': ['الشاشة'], 'estimatedCents': 150000,
        });
      }
      for (var i = 0; i < _sales; i++) {
        await api.post('/api/sales', {
          'items': [
            {'productId': products[i % products.length], 'qty': 1},
            {'productId': products[(i * 7) % products.length], 'qty': 2},
          ],
          'payments': [{'method': 'cash', 'amountCents': 7500}],
        });
      }
      stdout.writeln('seeded $_tickets tickets + $_sales sales in ${sw.elapsed.inSeconds}s');

      Future<void> time(String label, Future<Object?> Function() f) async {
        final s = Stopwatch()..start();
        for (var i = 0; i < 3; i++) {
          await f();
        }
        stdout.writeln('${(s.elapsedMilliseconds / 3).toStringAsFixed(0).padLeft(6)} ms  $label');
      }

      await time('dashboard', () => api.get('/api/dashboard'));
      await time('tickets active', () => api.get('/api/tickets', query: {'scope': 'active', 'limit': '200'}));
      await time('tickets all', () => api.get('/api/tickets', query: {'scope': 'all', 'limit': '200'}));
      await time('tickets search', () => api.get('/api/tickets', query: {'scope': 'all', 'q': 'عميل 5', 'limit': '200'}));
      await time('tickets overdue', () => api.get('/api/tickets', query: {'scope': 'overdue', 'limit': '200'}));
      await time('ticket detail', () async => api.get('/api/tickets/${((await api.get('/api/tickets', query: {'scope': 'all', 'limit': '1'}))['tickets'] as List).first['id']}'));
      await time('customers', () => api.get('/api/customers'));
      await time('customers search', () => api.get('/api/customers', query: {'q': '0101'}));
      await time('products', () => api.get('/api/products'));
      await time('products search', () => api.get('/api/products', query: {'q': 'صنف 1'}));
      await time('sales', () => api.get('/api/sales'));
      await time('cash current', () => api.get('/api/cash/current'));
      await time('reminders', () => api.get('/api/reminders'));
      await time('report month', () => api.get('/api/reports/summary'));
      await time('shop', () => api.get('/api/shop'));
      await time('audit', () => api.get('/api/audit'));
      // صور كتير (زي صور البطايق) بتتراكم مع الوقت
      final files = Directory('${dir.path}/files')..createSync(recursive: true);
      final photo = List<int>.generate(350 * 1024, (i) => (i * 31 + 7) % 251);
      for (var i = 0; i < 400; i++) {
        File('${files.path}/photo$i').writeAsBytesSync(photo);
      }
      final b = Stopwatch()..start();
      final backup = api.send('POST', '/api/backups', timeout: const Duration(minutes: 5));
      // وإحنا بنعمل نسخة، الأجهزة التانية لسه شغالة: أطول وقت استنى فيه أي طلب؟
      var worst = 0, count = 0;
      var done = false;
      unawaited(backup.whenComplete(() => done = true));
      while (!done) {
        final s = Stopwatch()..start();
        await api.get('/api/shop');
        if (s.elapsedMilliseconds > worst) worst = s.elapsedMilliseconds;
        count++;
      }
      await backup;
      stdout.writeln('${b.elapsedMilliseconds.toString().padLeft(6)} ms  backup with 400 photos (140 MB)');
      stdout.writeln('${worst.toString().padLeft(6)} ms  worst wait for another device during the backup ($count requests)');
    } finally {
      api.close();
      await server.stop();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 30)));
}
