import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late FixTrackServer server;
  late String base;
  late ApiClient owner;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_supervisor');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    base = 'http://127.0.0.1:${server.port}';
    owner = ApiClient(base);
    owner.token = (await owner.post('/api/setup', {
      'shopName': 'محل', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123',
    }))['token'] as String;
  });

  tearDown(() async {
    owner.close();
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

  Future<ApiClient> login(String username, String password, String role) async {
    await owner.post('/api/users', {'name': username, 'username': username, 'password': password, 'role': role});
    final c = ApiClient(base);
    c.token = (await c.post('/api/auth/login', {'username': username, 'password': password}))['token'] as String;
    return c;
  }

  test('supervisor: counts stock and sees drawer history, but no reports, users or withdrawals', () async {
    final sup = await login('mona', 'mona1234', 'supervisor');
    final rec = await login('sara', 'sara1234', 'reception');
    final product = (await owner.post('/api/products', {
      'name': 'جراب', 'category': 'جرابات', 'costCents': 3000, 'priceCents': 5000, 'qty': 10, 'lowStock': 2,
    }))['product'] as Map<String, dynamic>;

    await expectApiError(rec.post('/api/products/${product['id']}/adjust', {'setQty': 8, 'reason': 'count'}), 403);
    await sup.post('/api/products/${product['id']}/adjust', {'setQty': 8, 'reason': 'count'});
    expect((await owner.get('/api/products'))['products'][0]['qty'], 8);

    await sup.get('/api/cash/sessions');
    await expectApiError(rec.get('/api/cash/sessions'), 403);
    await expectApiError(sup.post('/api/cash/moves', {'type': 'withdraw', 'amountCents': 100, 'method': 'cash'}), 403);
    await expectApiError(sup.get('/api/reports/summary'), 403);
    await expectApiError(sup.get('/api/users'), 403);
    await expectApiError(sup.patch('/api/shop', {'name': 'x'}), 403);

    sup.close();
    rec.close();
  });

  test('upgrading an old database keeps users and lets the owner add a supervisor', () async {
    final tech = await login('ali', 'ali12345', 'technician');
    final ticket = await owner.post('/api/tickets', {
      'customer': {'name': 'أحمد علي', 'phone': '0100 123 4567'},
      'brand': 'Samsung', 'model': 'A55', 'problems': ['الشاشة'], 'estimatedCents': 1000,
      'technicianId': (await tech.get('/api/auth/me'))['user']['id'],
    });
    tech.close();
    await server.stop();

    // نرجّع الملف لنسخة ما قبل "مسؤول شفت" عشان الـ migration تتنفذ تاني على بيانات حقيقية
    final raw = sqlite3.open(p.join(dir.path, 'fixtrack.db'));
    raw.userVersion = 7;
    raw.close();

    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    base = 'http://127.0.0.1:${server.port}';
    owner.close();
    owner = ApiClient(base);
    owner.token = (await owner.post('/api/auth/login', {'username': 'owner', 'password': 'owner123'}))['token'] as String;

    final users = (await owner.get('/api/users'))['users'] as List;
    expect(users.map((u) => u['username']), containsAll(['owner', 'ali']));
    expect((await owner.get('/api/tickets/${ticket['ticket']['id']}'))['ticket']['id'], ticket['ticket']['id']);
    final sup = await login('mona', 'mona1234', 'supervisor');
    expect((await sup.get('/api/auth/me'))['user']['role'], 'supervisor');
    sup.close();
  });
}
