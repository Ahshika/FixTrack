import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FixTrackServer server;
  late ApiClient api;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_approval');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    api = ApiClient('http://127.0.0.1:${server.port}');
    api.token = (await api.post('/api/setup', {
      'shopName': 'محل', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123',
    }))['token'] as String;
  });

  tearDown(() async {
    api.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> intake() async => (await api.post('/api/tickets', {
        'customer': {'name': 'سارة', 'phone': '01001234567'},
        'brand': 'Samsung', 'model': 'A55', 'problems': ['الشاشة'], 'estimatedCents': 150000,
      }))['ticket'] as Map<String, dynamic>;

  Future<void> expectApiError(Future<Object?> f, int status) async {
    try {
      await f;
      fail('expected $status');
    } on ApiException catch (e) {
      expect(e.status, status, reason: e.message);
    }
  }

  test('approval request moves to waitingApproval; staff records yes', () async {
    final t = await intake();
    var d = await api.post('/api/tickets/${t['id']}/approval', {'totalCents': 220000, 'note': 'الفلاتة بايظة'});
    expect(d['ticket']['status'], 'waitingApproval');
    expect(d['ticket']['approvalState'], 'pending');
    expect(d['ticket']['approvalCents'], 220000);

    d = await api.post('/api/tickets/${t['id']}/approval/resolve', {'approved': true});
    expect(d['ticket']['status'], 'repairing');
    expect(d['ticket']['finalCents'], 220000);
    expect(d['ticket']['approvalState'], 'approved');
    await expectApiError(api.post('/api/tickets/${t['id']}/approval/resolve', {'approved': false}), 400);
  });

  test('rejection keeps old cost and waits for pickup', () async {
    final t = await intake();
    await api.post('/api/tickets/${t['id']}/approval', {'totalCents': 220000, 'note': 'x'});
    final d = await api.post('/api/tickets/${t['id']}/approval/resolve', {'approved': false});
    expect(d['ticket']['status'], 'cancelled');
    expect(d['ticket']['finalCents'], isNull);
    expect(d['ticket']['approvalState'], 'rejected');
  });

  test('pickup time shows up in today list and dashboard', () async {
    final t = await intake();
    final now = DateTime.now();
    final later = DateTime(now.year, now.month, now.day, 23, 30);
    await api.post('/api/tickets/${t['id']}/pickup', {'at': later.toIso8601String()});
    final today = await api.get('/api/tickets', query: {'scope': 'pickupToday'});
    expect((today['tickets'] as List).single['id'], t['id']);
    expect((await api.get('/api/dashboard'))['pickupsToday'], 1);
    await api.post('/api/tickets/${t['id']}/pickup', {'at': null});
    expect((await api.get('/api/dashboard'))['pickupsToday'], 0);
  });

  test('pickup hours validation', () async {
    await expectApiError(api.patch('/api/shop', {'pickupHours': {'days': [1], 'from': '22:00', 'to': '10:00', 'slotMinutes': 30}}), 400);
    final shop = await api.patch('/api/shop', {'pickupHours': {'days': [6, 0, 9], 'from': '10:00', 'to': '18:00', 'slotMinutes': 60}});
    expect(shop['pickupHours'], {'days': [0, 6], 'from': '10:00', 'to': '18:00', 'slotMinutes': 60});
  });

  test('tracking link defaults to the FixTrack site', () async {
    expect((await api.get('/api/shop'))['trackingBaseUrl'], 'https://fixtrack-7fcf9.web.app');
  });
}
