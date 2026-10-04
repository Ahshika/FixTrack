import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FixTrackServer server;
  late ApiClient api;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_test');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    api = ApiClient('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    api.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<String> setupShop() async {
    final res = await api.post('/api/setup', {
      'shopName': 'محل النور',
      'ownerName': 'أحمد',
      'username': 'Ahmed',
      'password': 'secret123',
    });
    return res['token'] as String;
  }

  Future<void> expectApiError(Future<Object?> f, int status) async {
    try {
      await f;
      fail('expected ApiException $status');
    } on ApiException catch (e) {
      expect(e.status, status, reason: e.message);
    }
  }

  test('info reports setup state', () async {
    var info = await api.get('/api/info');
    expect(info['app'], 'fixtrack');
    expect(info['setupDone'], false);
    await setupShop();
    info = await api.get('/api/info');
    expect(info['setupDone'], true);
    expect(info['shopName'], 'محل النور');
    expect(info['branchName'], 'الفرع الرئيسي');
  });

  test('setup only works once', () async {
    await setupShop();
    await expectApiError(setupShop(), 409);
  });

  test('login, me, logout', () async {
    await setupShop();
    await expectApiError(api.post('/api/auth/login', {'username': 'ahmed', 'password': 'wrong'}), 401);

    // اسم المستخدم مش حساس لحالة الحروف
    final res = await api.post('/api/auth/login', {'username': 'AHMED', 'password': 'secret123'});
    api.token = res['token'] as String;
    final me = await api.get('/api/auth/me');
    expect(me['user']['role'], 'owner');

    await api.post('/api/auth/logout');
    await expectApiError(api.get('/api/auth/me'), 401);
  });

  test('login is throttled after repeated failures', () async {
    await setupShop();
    for (var i = 0; i < 5; i++) {
      await expectApiError(api.post('/api/auth/login', {'username': 'ahmed', 'password': 'nope'}), 401);
    }
    await expectApiError(api.post('/api/auth/login', {'username': 'ahmed', 'password': 'secret123'}), 429);
  });

  test('owner manages users; technician cannot', () async {
    api.token = await setupShop();
    final created = await api.post('/api/users', {
      'name': 'محمد',
      'username': 'mohamed',
      'password': 'tech1234',
      'role': 'technician',
    });
    final techId = created['user']['id'] as String;
    await expectApiError(
      api.post('/api/users', {'name': 'x', 'username': 'mohamed', 'password': 'tech1234', 'role': 'technician'}),
      409,
    );

    final list = await api.get('/api/users');
    expect((list['users'] as List).length, 2);

    final tech = ApiClient(api.baseUrl);
    final login = await tech.post('/api/auth/login', {'username': 'mohamed', 'password': 'tech1234'});
    tech.token = login['token'] as String;
    await expectApiError(tech.get('/api/users'), 403);

    // إيقاف الحساب بيخرجه من الأجهزة فوراً
    await api.patch('/api/users/$techId', {'active': false});
    await expectApiError(tech.get('/api/auth/me'), 401);
    await expectApiError(tech.post('/api/auth/login', {'username': 'mohamed', 'password': 'tech1234'}), 403);
    tech.close();
  });

  test('last owner cannot be demoted or deactivated', () async {
    api.token = await setupShop();
    final me = await api.get('/api/auth/me');
    final id = me['user']['id'] as String;
    await expectApiError(api.patch('/api/users/$id', {'role': 'reception'}), 400);
    await expectApiError(api.patch('/api/users/$id', {'active': false}), 400);
  });

  test('changing password keeps current session and revokes others', () async {
    final first = await setupShop();
    final other = ApiClient(api.baseUrl);
    other.token = (await other.post('/api/auth/login', {'username': 'ahmed', 'password': 'secret123'}))['token'] as String;

    api.token = first;
    await expectApiError(api.post('/api/auth/password', {'currentPassword': 'bad', 'newPassword': 'newpass1'}), 400);
    await api.post('/api/auth/password', {'currentPassword': 'secret123', 'newPassword': 'newpass1'});
    await api.get('/api/auth/me');
    await expectApiError(other.get('/api/auth/me'), 401);
    other.close();
  });

  test('audit log records actions', () async {
    api.token = await setupShop();
    await api.post('/api/users', {'name': 'سارة', 'username': 'sara', 'password': 'pass1234', 'role': 'reception'});
    final audit = await api.get('/api/audit');
    final actions = (audit['entries'] as List).map((e) => e['action']).toList();
    expect(actions, containsAll(['shop.setup', 'user.create']));
  });

  test('data survives a restart', () async {
    await setupShop();
    await server.stop();
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    api.close();
    api = ApiClient('http://127.0.0.1:${server.port}');
    final res = await api.post('/api/auth/login', {'username': 'ahmed', 'password': 'secret123'});
    expect(res['user']['name'], 'أحمد');
  });
}
