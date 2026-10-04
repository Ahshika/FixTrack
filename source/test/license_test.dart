import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/core/license.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

final _realKey = File('../signing/license-private.key');

void main() {
  group('codes', () {
    late List<int> seed;
    late String pub;

    setUpAll(() async {
      final pair = await Ed25519().newKeyPair();
      seed = await pair.extractPrivateKeyBytes();
      pub = base64.encode((await pair.extractPublicKey()).bytes);
    });

    LicenseData data({String device = 'ABCDE-FGHJK', DateTime? exp}) => LicenseData(
          id: 'L1', shop: 'محل النور', device: device, plan: 'yearly', expires: exp, devices: 5, branches: 2, issued: DateTime.now());

    test('sign → verify round trip', () async {
      final code = await signLicense(data(exp: DateTime.utc(2030, 6)), seed);
      final lic = await verifyLicense(code, deviceCode: 'ABCDE-FGHJK', publicKey: pub);
      expect(lic.shop, 'محل النور');
      expect(lic.devices, 5);
      expect(lic.expires!.year, 2030);
    });

    test('code for another device is rejected', () async {
      final code = await signLicense(data(), seed);
      expect(() => verifyLicense(code, deviceCode: 'ZZZZZ-ZZZZZ', publicKey: pub), throwsA(isA<LicenseException>()));
    });

    test('tampered payload fails the signature', () async {
      final code = await signLicense(data(exp: DateTime(2027)), seed);
      final parts = code.split('.');
      final payload = jsonDecode(utf8.decode(base64Url.decode(parts[1].padRight((parts[1].length + 3) ~/ 4 * 4, '='))));
      payload['exp'] = '2099-01-01T00:00:00.000Z'; // حد بيحاول يطوّل الاشتراك
      final forged = 'FT1.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${parts[2]}';
      expect(() => verifyLicense(forged, deviceCode: 'ABCDE-FGHJK', publicKey: pub), throwsA(isA<LicenseException>()));
    });

    test('code signed with a different key is rejected by the real public key', () async {
      final code = await signLicense(data(), seed);
      expect(() => verifyLicense(code, deviceCode: 'ABCDE-FGHJK'), throwsA(isA<LicenseException>()));
    });

    test('device code is stable and formatted', () {
      final a = deviceCodeFor('server-123');
      expect(a, deviceCodeFor('server-123'));
      expect(a, matches(RegExp(r'^[A-Z2-9]{5}-[A-Z2-9]{5}$')));
      expect(a == deviceCodeFor('server-124'), false);
    });
  });

  group('server', () {
    late Directory dir;
    late FixTrackServer server;
    late ApiClient api;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fixtrack_license');
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

    Future<void> intake() => api.post('/api/tickets', {
          'customer': {'name': 'سارة', 'phone': '01001234567'},
          'brand': 'Samsung', 'model': 'A55', 'problems': ['الشاشة'],
        });

    test('new shop starts a 14-day trial; after it ends new work is blocked but data stays readable', () async {
      final s = await api.get('/api/license');
      expect(s['state'], 'trial');
      expect(s['daysLeft'], 13);
      await intake();

      server.db.setSetting('trial_started', DateTime.now().toUtc().subtract(const Duration(days: 15)).toIso8601String());
      expect((await api.get('/api/license'))['state'], 'expired');
      try {
        await intake();
        fail('should be blocked');
      } on ApiException catch (e) {
        expect(e.status, 402);
        expect(e.message, contains('التجربة'));
      }
      // الشغل القديم لسه متاح
      expect(((await api.get('/api/tickets', query: {'scope': 'all'}))['tickets'] as List).length, 1);
    });

    test('turning the clock back is detected', () async {
      server.db.setSetting('license_clock', DateTime.now().toUtc().add(const Duration(days: 10)).toIso8601String());
      expect((await api.get('/api/license'))['state'], 'tampered');
    });

    test('a real signed code activates the shop and lifts the trial limit', () async {
      final status = await api.get('/api/license');
      final device = status['deviceCode'] as String;
      final code = await signLicense(
        LicenseData(id: 'T-1', shop: 'محل', device: device, plan: 'yearly', expires: DateTime.now().add(const Duration(days: 365)), devices: 2, branches: 1, issued: DateTime.now()),
        base64.decode(_realKey.readAsStringSync().trim()),
      );
      server.db.setSetting('trial_started', DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String());
      final s = await api.post('/api/license', {'code': code});
      expect(s['state'], 'active');
      expect(s['devices'], 2);
      await intake();

      // حد 2 أجهزة: "owner" من جهازين مختلفين تمام، والتالت يترفض
      await api.post('/api/auth/login', {'username': 'owner', 'password': 'owner123', 'deviceName': 'موبايل 1'});
      await api.post('/api/auth/login', {'username': 'owner', 'password': 'owner123', 'deviceName': 'موبايل 2'});
      // نفس الجهاز يقدر يدخل تاني عادي
      await api.post('/api/auth/login', {'username': 'owner', 'password': 'owner123', 'deviceName': 'موبايل 1'});
      try {
        await api.post('/api/auth/login', {'username': 'owner', 'password': 'owner123', 'deviceName': 'موبايل 3'});
        fail('third device should be blocked');
      } on ApiException catch (e) {
        expect(e.status, 402);
      }
    }, skip: _realKey.existsSync() ? false : 'المفتاح السري مش موجود على الجهاز ده');

    test('garbage or foreign codes are rejected', () async {
      try {
        await api.post('/api/license', {'code': 'FT1.abc.def'});
        fail('should reject');
      } on ApiException catch (e) {
        expect(e.status, 400);
      }
    });
  });
}
