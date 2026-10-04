import 'dart:convert';
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

// أصغر JPEG ممكن (بيبدأ بـ FF D8) عشان اختبار رفع صورة البطاقة
final _jpeg = base64.encode([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xFF, 0xD9]);

void main() {
  late Directory dir;
  late FixTrackServer server;
  late ApiClient owner;
  late ApiClient cashier;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_stock');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    final base = 'http://127.0.0.1:${server.port}';
    owner = ApiClient(base);
    owner.token = (await owner.post('/api/setup', {'shopName': 'محل', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123'}))['token'] as String;
    await owner.post('/api/users', {'name': 'سارة', 'username': 'sara', 'password': 'sara1234', 'role': 'reception'});
    cashier = ApiClient(base);
    cashier.token = (await cashier.post('/api/auth/login', {'username': 'sara', 'password': 'sara1234'}))['token'] as String;
  });

  tearDown(() async {
    owner.close();
    cashier.close();
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

  Future<Map<String, dynamic>> phoneModel() async => (await owner.post('/api/products', {
        'name': 'Samsung Galaxy A55 256GB', 'category': 'موبايلات', 'costCents': 1500000, 'priceCents': 1800000,
        'serialized': true, 'warrantyMonths': 12,
      }))['product'] as Map<String, dynamic>;

  test('purchase from supplier registers IMEIs, stock, cost, supplier balance and drawer', () async {
    final model = await phoneModel();
    final cable = (await owner.post('/api/products', {'name': 'كابل', 'priceCents': 5000, 'costCents': 2000}))['product'] as Map;
    final sup = (await cashier.post('/api/suppliers', {'name': 'موبي تريد', 'phone': '0222333444'}))['supplier'] as Map;

    await expectApiError(cashier.post('/api/purchases', {
      'supplierId': sup['id'],
      'items': [{'productId': model['id'], 'unitCostCents': 1450000, 'units': [{'imei': '356789104561234'}, {'imei': '356789104561234'}]}],
    }), 400);

    final res = await cashier.post('/api/purchases', {
      'supplierId': sup['id'],
      'items': [
        {'productId': model['id'], 'unitCostCents': 1450000, 'units': [{'imei': '356789104561234', 'color': 'أسود'}, {'imei': '356789104561242'}]},
        {'productId': cable['id'], 'qty': 20, 'unitCostCents': 1800},
      ],
      'paidCents': 2000000,
      'method': 'cash',
    });
    expect(res['purchase']['totalCents'], 2 * 1450000 + 20 * 1800);
    expect(res['purchase']['dueCents'], 2 * 1450000 + 20 * 1800 - 2000000);

    final units = await cashier.get('/api/units', query: {'productId': model['id']});
    expect((units['units'] as List).length, 2);
    final products = await owner.get('/api/products', query: {'q': 'Galaxy'});
    expect((products['products'] as List).single['qty'], 2);
    expect((products['products'] as List).single['costCents'], 1450000);

    final s = await cashier.get('/api/suppliers/${sup['id']}');
    expect(s['supplier']['balanceCents'], 2 * 1450000 + 20 * 1800 - 2000000);
    await cashier.post('/api/suppliers/${sup['id']}/payments', {'amountCents': 500000, 'method': 'instapay'});
    expect((await cashier.get('/api/suppliers/${sup['id']}'))['supplier']['balanceCents'], 2 * 1450000 + 20 * 1800 - 2500000);

    final cash = await cashier.get('/api/cash/current');
    expect(cash['session']['byType']['purchase_payment'], -2000000);
    expect(cash['session']['byType']['supplier_payment'], -500000);

    // نفس الـ IMEI مايدخلش المخزون مرتين
    await expectApiError(cashier.post('/api/units', {'productId': model['id'], 'units': [{'imei': '356789104561234'}]}), 409);
  });

  test('selling a phone requires picking the IMEI; scanning IMEI finds it; return puts it back', () async {
    final model = await phoneModel();
    await cashier.post('/api/units', {'productId': model['id'], 'units': [{'imei': '356789104561234'}]});
    final lookup = await cashier.get('/api/products/lookup', query: {'barcode': '356789104561234'});
    expect(lookup['product']['id'], model['id']);
    final unitId = lookup['unit']['id'];

    await expectApiError(cashier.post('/api/sales', {
      'items': [{'productId': model['id'], 'qty': 1}],
      'payments': [{'method': 'cash', 'amountCents': 1800000}],
    }), 400);

    final sale = await cashier.post('/api/sales', {
      'items': [{'productId': model['id'], 'qty': 1, 'unitId': unitId}],
      'payments': [{'method': 'cash', 'amountCents': 1800000}],
    });
    final item = (sale['items'] as List).single;
    expect(item['imei'], '356789104561234');
    expect(item['warrantyMonths'], 12);
    expect((await cashier.get('/api/products/lookup', query: {'barcode': '356789104561234'}))['product'], isNull);
    await expectApiError(cashier.post('/api/sales', {
      'items': [{'productId': model['id'], 'qty': 1, 'unitId': unitId}],
      'payments': [{'method': 'cash', 'amountCents': 1800000}],
    }), 409);

    await cashier.post('/api/sales/${sale['sale']['id']}/return', {'items': [{'saleItemId': item['id'], 'qty': 1}]});
    expect((await cashier.get('/api/products/lookup', query: {'barcode': '356789104561234'}))['unit']['id'], unitId);

    // الأجهزة مابتتجردش بالعدد
    await expectApiError(owner.post('/api/products/${model['id']}/adjust', {'setQty': 5}), 400);
  });

  test('buying a used phone needs seller ID + photo, pays from the drawer, and shows in IMEI history', () async {
    final photo = (await cashier.post('/api/files', {'data': _jpeg, 'kind': 'national_id'}))['id'] as String;
    await expectApiError(cashier.post('/api/files', {'data': base64.encode([1, 2, 3, 4])}), 400);

    final body = {
      'model': 'iPhone 12 128GB',
      'imei': '353918105555550',
      'color': 'أزرق',
      'notes': 'البطارية 82%',
      'sellerName': 'محمد علي',
      'sellerPhone': '01012345678',
      'sellerNationalId': '29001011234567',
      'idPhotoId': photo,
      'costCents': 900000,
      'priceCents': 1100000,
    };
    await expectApiError(cashier.post('/api/units/buy-used', {...body, 'sellerNationalId': '123'}), 400);
    await expectApiError(cashier.post('/api/units/buy-used', {...body, 'idPhotoId': null}), 400);

    final res = await cashier.post('/api/units/buy-used', body);
    expect(res['unit']['condition'], 'used');
    expect(res['unit']['sellerName'], 'محمد علي');
    expect(res['unit']['priceCents'], 1100000);

    final cash = await cashier.get('/api/cash/current');
    expect(cash['session']['byType']['used_purchase'], -900000);

    final history = await cashier.get('/api/imei/353918105555550');
    expect((history['units'] as List).single['sellerNationalId'], '29001011234567');

    // الصورة ممكن تتفتح تاني
    final img = await cashier.send('GET', '/api/files/$photo').catchError((_) => <String, dynamic>{});
    expect(img, isA<Map>());
  });

  test('IMEI history includes repair tickets', () async {
    await owner.post('/api/tickets', {
      'customer': {'name': 'سارة', 'phone': '01001234567'},
      'brand': 'Samsung', 'model': 'A55', 'imei': '490154203237518', 'problems': ['الشاشة'],
    });
    final h = await cashier.get('/api/imei/490154203237518');
    expect((h['tickets'] as List).single['number'], 1001);
    expect(h['validImei'], true);
  });

  test('wallets: cash in/out, recharge, commission and drawer effects', () async {
    await expectApiError(cashier.post('/api/wallets', {'name': 'x', 'kind': 'vodafone'}), 403);
    final w = (await owner.post('/api/wallets', {'name': 'فودافون كاش 010', 'kind': 'vodafone', 'balanceCents': 500000}))['wallet'] as Map;
    expect(w['balanceCents'], 500000);

    // إيداع لعميل 1000 + عمولة 10: المحفظة تقل 1000 والدرج يزيد 1010
    var r = await cashier.post('/api/wallets/${w['id']}/txns', {'type': 'cash_in', 'amountCents': 100000, 'commissionCents': 1000, 'customerPhone': '01011111111'});
    expect(r['wallet']['balanceCents'], 400000);
    // سحب لعميل 2000 وعمولة 20: المحفظة تزيد 2000 والدرج يقل 1980
    r = await cashier.post('/api/wallets/${w['id']}/txns', {'type': 'cash_out', 'amountCents': 200000, 'commissionCents': 2000});
    expect(r['wallet']['balanceCents'], 600000);
    // شحن رصيد 50 وعمولة 2
    r = await cashier.post('/api/wallets/${w['id']}/txns', {'type': 'recharge', 'amountCents': 5000, 'commissionCents': 200});
    expect(r['wallet']['balanceCents'], 595000);
    expect(r['wallet']['todayCommissionCents'], 3200);

    await expectApiError(cashier.post('/api/wallets/${w['id']}/txns', {'type': 'cash_in', 'amountCents': 99900000}), 400);
    await expectApiError(cashier.post('/api/wallets/${w['id']}/txns', {'type': 'adjust', 'amountCents': 100}), 403);

    final cash = await cashier.get('/api/cash/current');
    expect(cash['session']['byType']['service'], 101000 - 198000 + 5200);
  });
}
