import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FixTrackServer server;
  late ApiClient api;

  Future<void> start() async {
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    api = ApiClient('http://127.0.0.1:${server.port}', token: api.token);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_repair');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    api = ApiClient('http://127.0.0.1:${server.port}');
    api.token = (await api.post('/api/setup', {'shopName': 'محل', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123'}))['token'] as String;
  });

  tearDown(() async {
    api.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<void> expectApiError(Future<Object?> f, int status) async {
    try {
      await f;
      fail('expected $status');
    } on ApiException catch (e) {
      expect(e.status, status, reason: e.message);
    }
  }

  Future<Map<String, dynamic>> intake({String? warrantyOf}) async => (await api.post('/api/tickets', {
        'customer': {'name': 'سارة', 'phone': '01001234567'},
        'brand': 'Samsung', 'model': 'A55', 'imei': '490154203237518', 'problems': ['الشاشة'], 'estimatedCents': 150000,
        'warrantyOf': ?warrantyOf,
      }))['ticket'] as Map<String, dynamic>;

  Future<void> deliver(Map t, {int? warrantyDays}) async => api.post('/api/tickets/${t['id']}/deliver', {
        'pin': t['pickupPin'], 'paymentCents': 150000, 'warrantyDays': ?warrantyDays,
      });

  test('delivery sets warranty; a warranty return links to the original', () async {
    final t = await intake();
    await deliver(t, warrantyDays: 60);
    final d = await api.get('/api/tickets/${t['id']}');
    final until = DateTime.parse(d['ticket']['warrantyUntil'] as String);
    expect(until.difference(DateTime.now()).inDays, inInclusiveRange(59, 60));

    final check = await api.get('/api/warranty-check', query: {'phone': '01001234567'});
    expect((check['tickets'] as List).single['id'], t['id']);
    final byImei = await api.get('/api/warranty-check', query: {'imei': '490154203237518'});
    expect((byImei['tickets'] as List).length, 1);

    final ret = await intake(warrantyOf: t['id'] as String);
    final rd = await api.get('/api/tickets/${ret['id']}');
    expect(rd['ticket']['warrantyOf'], t['id']);
    expect(rd['warrantyOrigin']['number'], 1001);
    expect(((await api.get('/api/tickets/${t['id']}'))['warrantyReturns'] as List).single['number'], 1002);
  });

  test('expired warranty cannot be used', () async {
    final t = await intake();
    await deliver(t, warrantyDays: 30);
    server.db.execute('UPDATE tickets SET warranty_until = ? WHERE id = ?', [DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(), t['id']]);
    await expectApiError(intake(warrantyOf: t['id'] as String), 400);
  });

  test('parts used in a repair come out of stock and can be added to the bill', () async {
    final screen = (await api.post('/api/products', {'name': 'شاشة A55 أصلي', 'costCents': 80000, 'priceCents': 120000, 'qty': 3}))['product'] as Map;
    final t = await intake();
    var d = await api.post('/api/tickets/${t['id']}/parts', {'productId': screen['id'], 'qty': 1, 'addToBill': true});
    expect((d['parts'] as List).single['costCents'], 80000);
    expect(d['ticket']['finalCents'], 150000 + 120000);
    expect(((await api.get('/api/products', query: {'q': 'شاشة'}))['products'] as List).single['qty'], 2);

    final partId = (d['parts'] as List).single['id'];
    d = await api.delete('/api/tickets/${t['id']}/parts/$partId');
    expect(d['parts'], isEmpty);
    expect(((await api.get('/api/products', query: {'q': 'شاشة'}))['products'] as List).single['qty'], 3);
  });

  test('reminders become due after 3 days ready and clear once sent', () async {
    final t = await intake();
    await api.post('/api/tickets/${t['id']}/status', {'status': 'ready'});
    expect((await api.get('/api/reminders'))['tickets'], isEmpty);

    server.db.execute('UPDATE tickets SET ready_at = ? WHERE id = ?', [DateTime.now().toUtc().subtract(const Duration(days: 4)).toIso8601String(), t['id']]);
    final due = (await api.get('/api/reminders'))['tickets'] as List;
    expect(due.single['daysWaiting'], 4);

    final msg = await api.get('/api/tickets/${t['id']}/message', query: {'event': 'reminder'});
    expect(msg['body'], contains('من 4 يوم'));
    await api.post('/api/tickets/${t['id']}/messages', {'channel': 'whatsapp', 'event': 'reminder', 'body': msg['body']});
    expect((await api.get('/api/reminders'))['tickets'], isEmpty);

    // بعد أسبوع بيرجع يحتاج تذكير تاني
    server.db.execute('UPDATE tickets SET ready_at = ? WHERE id = ?', [DateTime.now().toUtc().subtract(const Duration(days: 8)).toIso8601String(), t['id']]);
    expect(((await api.get('/api/reminders'))['tickets'] as List).length, 1);
  });

  test('technician commission settings are saved', () async {
    final tech = (await api.post('/api/users', {'name': 'محمد', 'username': 'tech', 'password': 'tech1234', 'role': 'technician'}))['user'] as Map;
    final u = await api.patch('/api/users/${tech['id']}', {'commissionType': 'percent', 'commissionValue': 2500});
    expect(u['user']['commissionType'], 'percent');
    expect(u['user']['commissionValue'], 2500);
  });

  test('backup and restore bring the data back after restart', () async {
    await intake();
    final b = await api.post('/api/backups');
    final name = (b['backups'] as List).first['name'] as String;
    expect(name, endsWith('.zip'));

    await intake(); // جهاز تاني بعد النسخة
    expect(((await api.get('/api/tickets', query: {'scope': 'all'}))['tickets'] as List).length, 2);

    await api.post('/api/backups/restore', {'name': name});
    await server.stop();
    await start();
    final after = await api.get('/api/tickets', query: {'scope': 'all'});
    expect((after['tickets'] as List).length, 1, reason: 'restored to the backup state');
    // نسخة من البيانات قبل الاسترجاع اتحفظت للاحتياط
    expect(Directory('${dir.path}/backups').listSync().any((f) => f.path.contains('before-restore')), true);
  });

  test('backup folder must exist on the server machine', () async {
    await expectApiError(api.patch('/api/backups/settings', {'backupDir': r'Z:\no\such\folder'}), 400);
    final ext = await Directory.systemTemp.createTemp('fixtrack_ext');
    final res = await api.patch('/api/backups/settings', {'backupDir': ext.path});
    expect(res['backupDir'], ext.path);
    expect(Directory('${ext.path}/FixTrack Backups').listSync().length, 1);
    await ext.delete(recursive: true);
  });
}
