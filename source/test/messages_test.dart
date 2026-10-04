import 'dart:convert';
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/core/messages.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('templates', () {
    test('drops lines whose variables are empty', () {
      final out = renderTemplate('أهلاً {customer}\nتابع من هنا: {link}\n{shop}', {
        'customer': 'أحمد',
        'link': null,
        'shop': 'محل النور',
      });
      expect(out, 'أهلاً أحمد\nمحل النور');
    });

    test('keeps unknown placeholders untouched', () {
      expect(renderTemplate('{foo} {customer}', {'customer': 'x'}), '{foo} x');
    });

    test('whatsapp number format', () {
      expect(whatsappNumber('0100 123 4567'), '201001234567');
      expect(whatsappNumber('+201001234567'), '201001234567');
    });
  });

  group('server', () {
    late Directory dir;
    late FixTrackServer server;
    late ApiClient api;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fixtrack_msgs');
      server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
      await server.start();
      api = ApiClient('http://127.0.0.1:${server.port}');
      api.token = (await api.post('/api/setup', {
        'shopName': 'محل النور',
        'shopPhone': '0222222222',
        'ownerName': 'أحمد',
        'username': 'owner',
        'password': 'owner123',
      }))['token'] as String;
    });

    tearDown(() async {
      api.close();
      await server.stop();
      await dir.delete(recursive: true);
    });

    Future<Map<String, dynamic>> intake() async => (await api.post('/api/tickets', {
          'customer': {'name': 'سارة', 'phone': '01001234567'},
          'brand': 'Samsung',
          'model': 'A55',
          'problems': ['الشاشة'],
          'estimatedCents': 250000,
          'depositCents': 50000,
        }))['ticket'] as Map<String, dynamic>;

    test('shop profile defaults and update', () async {
      var shop = await api.get('/api/shop');
      expect(shop['name'], 'محل النور');
      expect(shop['receiptPaper'], '80mm');
      expect((shop['rules'] as Map)['ready'], 'whatsapp');

      shop = await api.patch('/api/shop', {
        'phone': '01111111111',
        'receiptPaper': '58mm',
        'trackingBaseUrl': 'https://fixtrack-demo.web.app/',
        'rules': {'ready': 'sms', 'bogus': 'sms'},
        'templates': {'ready': 'جاهز يا {customer}'},
      });
      expect(shop['phone'], '01111111111');
      expect(shop['receiptPaper'], '58mm');
      expect(shop['trackingBaseUrl'], 'https://fixtrack-demo.web.app');
      expect((shop['rules'] as Map)['ready'], 'sms');
      expect((shop['rules'] as Map).containsKey('bogus'), false);
      expect((shop['templates'] as Map)['ready'], 'جاهز يا {customer}');
    });

    test('logo must be a small PNG', () async {
      try {
        await api.put('/api/shop/logo', {'png': base64.encode([1, 2, 3, 4, 5, 6, 7, 8, 9])});
        fail('should reject');
      } on ApiException catch (e) {
        expect(e.status, 400);
      }
      final png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
      await api.put('/api/shop/logo', {'png': base64.encode(png)});
      expect((await api.get('/api/shop'))['logoBase64'], base64.encode(png));
    });

    test('message preview renders ticket data and tracking link', () async {
      await api.patch('/api/shop', {'trackingBaseUrl': 'https://x.web.app'});
      final t = await intake();
      final m = await api.get('/api/tickets/${t['id']}/message', query: {'event': 'received'});
      expect(m['whatsapp'], '201001234567');
      final body = m['body'] as String;
      expect(body, contains('سارة'));
      expect(body, contains('1001'));
      expect(body, contains(t['pickupPin']));
      expect(body, contains('https://x.web.app/t/'));
      // مفيش موعد متوقع، فالسطر بتاعه اتشال
      expect(body.contains('الموعد المتوقع'), false);
    });

    test('whatsapp messages are logged on the ticket', () async {
      final t = await intake();
      await api.post('/api/tickets/${t['id']}/messages', {'channel': 'whatsapp', 'event': 'custom', 'body': 'أهلاً'});
      final d = await api.get('/api/tickets/${t['id']}');
      final msgs = d['messages'] as List;
      expect(msgs.single['status'], 'opened');
      expect(msgs.single['userName'], 'أحمد');
    });

    test('auto SMS is queued on ready, claimed once, and reported', () async {
      await api.patch('/api/shop', {'rules': {'ready': 'sms', 'received': 'off'}});
      final t = await intake();
      expect((await api.get('/api/messages/queue'))['messages'], isEmpty, reason: 'received rule is off');

      await api.post('/api/tickets/${t['id']}/status', {'status': 'ready'});
      final claimed = (await api.get('/api/messages/queue', query: {'device': 'phone-1'}))['messages'] as List;
      expect(claimed.length, 1);
      expect(claimed.single['phone'], '01001234567');
      expect(claimed.single['body'], contains('جاهز'));
      // مابيترجعش لجهاز تاني طول ما الأول لسه بيبعته
      expect((await api.get('/api/messages/queue', query: {'device': 'phone-2'}))['messages'], isEmpty);

      await api.post('/api/messages/${claimed.single['id']}/result', {'ok': true});
      final d = await api.get('/api/tickets/${t['id']}');
      expect((d['messages'] as List).single['status'], 'sent');
    });

    test('scanning the receipt QR finds the ticket', () async {
      final t = await intake();
      final token = t['publicToken'] as String;
      final res = await api.get('/api/tickets', query: {'q': 'https://x.web.app/t/$token', 'scope': 'all'});
      expect((res['tickets'] as List).single['id'], t['id']);
    });
  });
}
