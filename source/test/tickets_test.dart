import 'dart:convert';
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/core/ticket_status.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:fixtrack/src/server/secret_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FixTrackServer server;
  late ApiClient owner;
  late ApiClient tech;
  late String techId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_tickets');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    final base = 'http://127.0.0.1:${server.port}';
    owner = ApiClient(base);
    owner.token = (await owner.post('/api/setup', {
      'shopName': 'محل',
      'ownerName': 'أحمد',
      'username': 'owner',
      'password': 'owner123',
    }))['token'] as String;
    techId = (await owner.post('/api/users', {
      'name': 'محمد',
      'username': 'tech',
      'password': 'tech1234',
      'role': 'technician',
    }))['user']['id'] as String;
    tech = ApiClient(base);
    tech.token = (await tech.post('/api/auth/login', {'username': 'tech', 'password': 'tech1234'}))['token'] as String;
  });

  tearDown(() async {
    owner.close();
    tech.close();
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<void> expectApiError(Future<Object?> f, int status) async {
    try {
      await f;
      fail('expected ApiException $status');
    } on ApiException catch (e) {
      expect(e.status, status, reason: e.message);
    }
  }

  Future<Map<String, dynamic>> intake({String phone = '0100 123 4567', String? technician, int deposit = 50000}) async {
    final res = await owner.post('/api/tickets', {
      'customer': {'name': 'أحمد علي', 'phone': phone},
      'brand': 'Samsung',
      'model': 'Galaxy A55',
      'problems': ['الشاشة'],
      'problemDesc': 'الشاشة مش شغالة',
      'lockType': 'pin',
      'lockSecret': '1234',
      'estimatedCents': 250000,
      'depositCents': deposit,
      'depositMethod': 'cash',
      'technicianId': ?technician,
      'dueAt': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
    });
    return res['ticket'] as Map<String, dynamic>;
  }

  test('intake creates customer, ticket, deposit; numbers are sequential', () async {
    final t1 = await intake();
    expect(t1['number'], 1001);
    expect(t1['status'], 'received');
    expect(t1['paidCents'], 50000);
    expect(t1['customerName'], 'أحمد علي');
    expect((t1['pickupPin'] as String).length, 4);
    expect(t1['hasLockSecret'], true);
    expect(t1.containsKey('lockSecret'), false);

    // نفس العميل بالرقم مكتوب بشكل تاني (أرقام عربي + كود مصر)
    final lookup = await owner.get('/api/customers/lookup', query: {'phone': '+20 ١٠٠١٢٣٤٥٦٧'});
    expect(lookup['customer']['name'], 'أحمد علي');

    final t2 = await owner.post('/api/tickets', {
      'customer': {'id': lookup['customer']['id']},
      'brand': 'iPhone',
      'model': '13',
      'problems': ['البطارية'],
    });
    expect(t2['ticket']['number'], 1002);
    final customers = await owner.get('/api/customers');
    expect((customers['customers'] as List).length, 1);
    expect(customers['customers'][0]['ticketsCount'], 2);
  });

  test('search by number, phone, name, model', () async {
    await intake();
    for (final q in ['1001', '01001234567', 'أحمد', 'A55']) {
      final res = await owner.get('/api/tickets', query: {'q': q, 'scope': 'all'});
      expect((res['tickets'] as List).length, 1, reason: 'search "$q"');
    }
    final none = await owner.get('/api/tickets', query: {'q': 'nokia'});
    expect(none['tickets'], isEmpty);
  });

  test('technician sees only assigned tickets and limited actions', () async {
    final mine = await intake(technician: techId);
    final other = await intake(phone: '01111111111');

    final list = await tech.get('/api/tickets');
    expect((list['tickets'] as List).map((t) => t['id']), [mine['id']]);
    await expectApiError(tech.get('/api/tickets/${other['id']}'), 403);

    final detail = await tech.get('/api/tickets/${mine['id']}');
    expect(detail['ticket'].containsKey('pickupPin'), false);

    // الفني يقدر يغيّر المرحلة ويشوف رمز القفل
    await tech.post('/api/tickets/${mine['id']}/status', {'status': 'repairing'});
    final lock = await tech.get('/api/tickets/${mine['id']}/lock');
    expect(lock['secret'], '1234');

    // بس مايقدرش يغيّر السعر أو يستلم فلوس أو يسلّم
    await expectApiError(tech.patch('/api/tickets/${mine['id']}', {'estimatedCents': 1}), 403);
    await expectApiError(tech.post('/api/tickets/${mine['id']}/payments', {'amountCents': 100}), 403);
    await expectApiError(tech.post('/api/tickets/${mine['id']}/deliver', {'pin': '0000'}), 403);
    await tech.patch('/api/tickets/${mine['id']}', {'dueAt': DateTime.now().toIso8601String()});
  });

  test('reception cannot reveal lock secret', () async {
    await owner.post('/api/users', {'name': 'سارة', 'username': 'sara', 'password': 'sara1234', 'role': 'reception'});
    final rec = ApiClient(owner.baseUrl);
    rec.token = (await rec.post('/api/auth/login', {'username': 'sara', 'password': 'sara1234'}))['token'] as String;
    final t = await intake(technician: techId);
    await expectApiError(rec.get('/api/tickets/${t['id']}/lock'), 403);
    rec.close();
  });

  test('status timeline and dashboard counts', () async {
    final t = await intake();
    for (final s in [TicketStatus.diagnosing, TicketStatus.repairing, TicketStatus.ready]) {
      await owner.post('/api/tickets/${t['id']}/status', {'status': s.name});
    }
    await expectApiError(owner.post('/api/tickets/${t['id']}/status', {'status': 'delivered'}), 400);

    final detail = await owner.get('/api/tickets/${t['id']}');
    final statusEvents = (detail['events'] as List).where((e) => e['type'] == 'status').map((e) => e['to']).toList();
    expect(statusEvents, ['diagnosing', 'repairing', 'ready']);

    final dash = await owner.get('/api/dashboard');
    expect(dash['receivedToday'], 1);
    expect(dash['ready'], 1);
    expect(dash['inProgress'], 0);
    expect(dash['collectedTodayCents'], 50000);
  });

  test('overdue detection', () async {
    final t = await intake();
    await owner.patch('/api/tickets/${t['id']}', {
      'dueAt': DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
    });
    final overdue = await owner.get('/api/tickets', query: {'scope': 'overdue'});
    expect((overdue['tickets'] as List).single['overdue'], true);
    expect((await owner.get('/api/dashboard'))['overdue'], 1);
  });

  test('delivery requires correct PIN and full payment', () async {
    final t = await intake();
    final pin = t['pickupPin'] as String;
    final wrong = pin == '0000' ? '1111' : '0000';
    await expectApiError(owner.post('/api/tickets/${t['id']}/deliver', {'pin': wrong}), 400);
    // باقي 2000 ج.م
    await expectApiError(owner.post('/api/tickets/${t['id']}/deliver', {'pin': pin}), 400);

    final res = await owner.post('/api/tickets/${t['id']}/deliver', {
      'pin': pin,
      'paymentCents': 200000,
      'paymentMethod': 'vodafoneCash',
    });
    expect(res['ticket']['status'], 'delivered');
    expect(res['ticket']['paidCents'], 250000);
    expect(res['ticket']['hasLockSecret'], false, reason: 'lock secret is wiped on delivery');
    await expectApiError(owner.post('/api/tickets/${t['id']}/deliver', {'pin': pin}), 400);
  });

  test('owner can deliver without PIN and with debt when explicit', () async {
    final t = await intake(deposit: 0);
    final res = await owner.post('/api/tickets/${t['id']}/deliver', {'override': true, 'allowDebt': true});
    expect(res['ticket']['status'], 'delivered');
    final last = (res['events'] as List).last;
    expect(last['note'], contains('بدون كود'));
  });

  test('payments and refunds', () async {
    final t = await intake();
    await owner.post('/api/tickets/${t['id']}/payments', {'amountCents': 100000, 'method': 'instapay', 'kind': 'payment'});
    await expectApiError(
      owner.post('/api/tickets/${t['id']}/payments', {'amountCents': 999999, 'kind': 'refund'}),
      400,
    );
    final res = await owner.post('/api/tickets/${t['id']}/payments', {'amountCents': 20000, 'kind': 'refund'});
    expect(res['ticket']['paidCents'], 130000);
    expect((res['payments'] as List).length, 3);
  });

  test('secret box round-trips and detects tampering', () {
    final box = SecretBox(List<int>.generate(32, (i) => i));
    final sealed = box.seal('pattern-1-5-9-6');
    expect(sealed.contains('pattern'), false);
    expect(box.open(sealed), 'pattern-1-5-9-6');
    expect(box.seal('same') == box.seal('same'), false, reason: 'random nonce');
    final bytes = base64.decode(sealed)..[20] ^= 1;
    expect(box.open(base64.encode(bytes)), isNull);
    expect(SecretBox(List<int>.filled(32, 7)).open(sealed), isNull, reason: 'wrong key');
  });

  test('phone normalization', () {
    expect(normalizePhone('+20 100 123 4567'), '01001234567');
    expect(normalizePhone('٠١٠٠١٢٣٤٥٦٧'), '01001234567');
    expect(normalizePhone('0020-100-123-4567'), '01001234567');
  });
}
