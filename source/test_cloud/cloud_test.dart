// تجربة حقيقية مع Firebase (بتعمل بيانات تجريبية وتمسحها). مش جزء من الاختبارات العادية.
// التشغيل: flutter test test_cloud
import 'dart:convert';
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/core/firebase_config.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const base = 'https://firestore.googleapis.com/v1/projects/$firebaseProjectId/databases/(default)/documents';

void main() {
  test('ticket syncs to tracking page and customer booking comes back', () async {
    final dir = await Directory.systemTemp.createTemp('fixtrack_cloud');
    final server = FixTrackServer(dataDir: dir.path, requestedPort: 0);
    await server.start();
    final api = ApiClient('http://127.0.0.1:${server.port}');
    try {
      api.token = (await api.post('/api/setup', {
        'shopName': 'محل تجربة FixTrack',
        'shopPhone': '01000000000',
        'ownerName': 'تجربة',
        'username': 'cloudtest',
        'password': 'cloud123',
      }))['token'] as String;
      final t = (await api.post('/api/tickets', {
        'customer': {'name': 'عميل تجريبي', 'phone': '01000000001'},
        'brand': 'Samsung',
        'model': 'A55',
        'problems': ['الشاشة'],
        'estimatedCents': 150000,
        'depositCents': 50000,
      }))['ticket'] as Map<String, dynamic>;
      final token = t['publicToken'] as String;

      await server.syncNow();
      expect(server.cloudError, anyOf(isNull, isEmpty), reason: server.cloudError);

      // 1) أي حد معاه اللينك يقرا الصفحة من غير تسجيل دخول
      var doc = await http.get(Uri.parse('$base/tracking/$token?key=$firebaseApiKey'));
      expect(doc.statusCode, 200, reason: doc.body);
      var fields = (jsonDecode(doc.body) as Map)['fields'] as Map;
      expect(fields['status']['stringValue'], 'received');
      expect(fields['customerName']['stringValue'], 'عميل');
      expect(fields.containsKey('customerPhone'), false);
      final ownerUid = fields['ownerUid']['stringValue'] as String;

      // 2) مينفعش حد من برا يعدّل الصفحة
      final hack = await http.patch(
        Uri.parse('$base/tracking/$token?key=$firebaseApiKey'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'fields': {'status': {'stringValue': 'ready'}, 'ownerUid': {'stringValue': ownerUid}}}),
      );
      expect(hack.statusCode, 403);

      // 3) مينفعش حد يشوف قايمة الأجهزة
      final list = await http.get(Uri.parse('$base/tracking?key=$firebaseApiKey'));
      expect(list.statusCode, 403);

      // 4) العميل يحجز معاد وهو جاهز
      await api.post('/api/tickets/${t['id']}/status', {'status': 'ready'});
      await server.syncNow();
      final slot = _nextValidSlot();
      final action = await http.post(
        Uri.parse('$base/actions?key=$firebaseApiKey'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'token': {'stringValue': token},
            'ownerUid': {'stringValue': ownerUid},
            'type': {'stringValue': 'pickup'},
            'slot': {'timestampValue': slot.toUtc().toIso8601String()},
          },
        }),
      );
      expect(action.statusCode, 200, reason: action.body);

      // مينفعش يوافق على تكلفة مفيش طلب ليها
      final badApprove = await http.post(
        Uri.parse('$base/actions?key=$firebaseApiKey'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'fields': {'token': {'stringValue': token}, 'ownerUid': {'stringValue': ownerUid}, 'type': {'stringValue': 'approve'}}}),
      );
      expect(badApprove.statusCode, 403);

      await server.syncNow();
      final detail = await api.get('/api/tickets/${t['id']}');
      expect(DateTime.parse(detail['ticket']['pickupAt'] as String).isAtSameMomentAs(slot), true);

      // 5) طلب موافقة ← العميل يوافق من الصفحة ← التكلفة تتغير والجهاز يرجع للإصلاح
      await api.post('/api/tickets/${t['id']}/approval', {'totalCents': 220000, 'note': 'الفلاتة كمان بايظة'});
      await server.syncNow();
      final approve = await http.post(
        Uri.parse('$base/actions?key=$firebaseApiKey'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'fields': {'token': {'stringValue': token}, 'ownerUid': {'stringValue': ownerUid}, 'type': {'stringValue': 'approve'}}}),
      );
      expect(approve.statusCode, 200, reason: approve.body);
      await server.syncNow();
      final after = await api.get('/api/tickets/${t['id']}');
      expect(after['ticket']['status'], 'repairing');
      expect(after['ticket']['finalCents'], 220000);
      expect(after['ticket']['approvalState'], 'approved');

      await server.syncNow();
      doc = await http.get(Uri.parse('$base/tracking/$token?key=$firebaseApiKey'));
      fields = (jsonDecode(doc.body) as Map)['fields'] as Map;
      expect(fields['status']['stringValue'], 'repairing');
    } finally {
      await server.cleanupCloudForTests();
      api.close();
      await server.stop();
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

DateTime _nextValidSlot() {
  // الافتراضي: كل الأيام ما عدا الجمعة، من 12 لـ 10 بالليل، كل نص ساعة
  var d = DateTime.now().add(const Duration(days: 1));
  while (d.weekday == DateTime.friday) {
    d = d.add(const Duration(days: 1));
  }
  return DateTime(d.year, d.month, d.day, 14, 30);
}
