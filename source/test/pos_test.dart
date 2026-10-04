import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/server/api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late FixTrackServer server;
  late ApiClient owner;
  late ApiClient cashier;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fixtrack_pos');
    server = FixTrackServer(dataDir: dir.path, requestedPort: 0, cloudSync: false);
    await server.start();
    final base = 'http://127.0.0.1:${server.port}';
    owner = ApiClient(base);
    owner.token = (await owner.post('/api/setup', {
      'shopName': 'محل', 'ownerName': 'أحمد', 'username': 'owner', 'password': 'owner123',
    }))['token'] as String;
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

  Future<Map<String, dynamic>> product(String name, {String? barcode, int cost = 3000, int price = 5000, int qty = 10}) async =>
      (await owner.post('/api/products', {
        'name': name, 'barcode': ?barcode, 'category': 'جرابات', 'costCents': cost, 'priceCents': price, 'qty': qty, 'lowStock': 2,
      }))['product'] as Map<String, dynamic>;

  test('products: create, barcode lookup, duplicate barcode, low stock', () async {
    final p = await product('جراب A55 شفاف', barcode: '6221234567890', qty: 2);
    expect(p['qty'], 2);
    final found = await cashier.get('/api/products/lookup', query: {'barcode': '6221234567890'});
    expect(found['product']['id'], p['id']);
    await expectApiError(product('تاني', barcode: '6221234567890'), 409);
    final low = await owner.get('/api/products', query: {'low': '1'});
    expect((low['products'] as List).length, 1);
    expect(low['stockValueCents'], 6000);
    // الكاشير مايشوفش قيمة المخزون ومايعدلش سعر الشرا
    expect((await cashier.get('/api/products')).containsKey('stockValueCents'), false);
    await expectApiError(cashier.patch('/api/products/${p['id']}', {'costCents': 1}), 403);
  });

  test('generated barcodes are valid EAN-13 and unique', () async {
    final a = (await owner.post('/api/products/barcode'))['barcode'] as String;
    expect(a.length, 13);
    expect(a.startsWith('20'), true);
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(a[i]) * (i.isEven ? 1 : 3);
    }
    expect(int.parse(a[12]), (10 - sum % 10) % 10);
  });

  test('cash sale lowers stock and lands in the drawer', () async {
    final p = await product('شاحن سامسونج', price: 25000);
    final s = await cashier.post('/api/sales', {
      'items': [{'productId': p['id'], 'qty': 2}],
      'payments': [{'method': 'cash', 'amountCents': 50000}],
    });
    expect(s['sale']['number'], 1);
    expect(s['sale']['totalCents'], 50000);
    expect(s['sale']['dueCents'], 0);
    final prod = await owner.get('/api/products', query: {'q': 'شاحن'});
    expect((prod['products'] as List).single['qty'], 8);

    final cash = await cashier.get('/api/cash/current');
    expect(cash['session']['byMethod']['cash'], 50000);
    expect(cash['session']['expectedCashCents'], 50000);
  });

  test('credit sale requires a customer and shows in their balance; collecting reduces it', () async {
    final p = await product('سماعة', price: 40000);
    await expectApiError(cashier.post('/api/sales', {'items': [{'productId': p['id'], 'qty': 1}], 'payments': []}), 400);

    final c = (await cashier.post('/api/customers', {'name': 'كريم', 'phone': '01112223334'}))['customer'] as Map;
    await cashier.post('/api/sales', {
      'customerId': c['id'],
      'items': [{'productId': p['id'], 'qty': 1}],
      'payments': [{'method': 'cash', 'amountCents': 10000}],
    });
    var ledger = await cashier.get('/api/customers/${c['id']}/ledger');
    expect(ledger['balanceCents'], 30000);

    await expectApiError(cashier.post('/api/customers/${c['id']}/payments', {'amountCents': 50000}), 400);
    await cashier.post('/api/customers/${c['id']}/payments', {'amountCents': 20000, 'method': 'vodafoneCash'});
    ledger = await cashier.get('/api/customers/${c['id']}/ledger');
    expect(ledger['balanceCents'], 10000);
    final cash = await cashier.get('/api/cash/current');
    expect(cash['session']['byMethod']['vodafoneCash'], 20000);
  });

  test('discount rules and selling below price', () async {
    final p = await product('اسكرينة', price: 10000);
    // الافتراضي: الكاشير يقدر يعمل خصم
    final s = await cashier.post('/api/sales', {
      'items': [{'productId': p['id'], 'qty': 3}],
      'discountCents': 5000,
      'payments': [{'method': 'cash', 'amountCents': 25000}],
    });
    expect(s['sale']['totalCents'], 25000);
    await expectApiError(
      cashier.post('/api/sales', {'items': [{'productId': p['id'], 'qty': 1}], 'payments': [{'method': 'cash', 'amountCents': 99999}]}),
      400,
    );
  });

  test('returns restock and refund cash, credit is reduced first', () async {
    final p = await product('كابل', price: 5000);
    final c = (await cashier.post('/api/customers', {'name': 'منى', 'phone': '01005556667'}))['customer'] as Map;
    final s = await cashier.post('/api/sales', {
      'customerId': c['id'],
      'items': [{'productId': p['id'], 'qty': 4}],
      'payments': [{'method': 'cash', 'amountCents': 15000}],
    });
    final itemId = (s['items'] as List).single['id'];
    // باقي آجل 5000؛ مرتجع 2 كابل (10000): أول 5000 بتلغي الآجل، و5000 بترجع كاش
    final r = await cashier.post('/api/sales/${s['sale']['id']}/return', {'items': [{'saleItemId': itemId, 'qty': 2}], 'method': 'cash'});
    expect(r['returnValueCents'], 10000);
    expect(r['refundCents'], 5000);
    expect(r['sale']['dueCents'], 0);
    expect((await cashier.get('/api/customers/${c['id']}/ledger'))['balanceCents'], 0);
    expect(((await owner.get('/api/products', query: {'q': 'كابل'}))['products'] as List).single['qty'], 8);
    await expectApiError(cashier.post('/api/sales/${s['sale']['id']}/return', {'items': [{'saleItemId': itemId, 'qty': 3}]}), 400);
    final cash = await cashier.get('/api/cash/current');
    expect(cash['session']['expectedCashCents'], 10000);
  });

  test('repair payments go to the same drawer; expenses and closing the day', () async {
    await owner.post('/api/tickets', {
      'customer': {'name': 'سارة', 'phone': '01001234567'},
      'brand': 'Samsung', 'model': 'A55', 'problems': ['الشاشة'], 'estimatedCents': 150000, 'depositCents': 50000,
    });
    await cashier.post('/api/cash/moves', {'type': 'expense', 'amountCents': 2000, 'category': 'أكل وشرب'});
    await expectApiError(cashier.post('/api/cash/moves', {'type': 'withdraw', 'amountCents': 1000}), 403);

    var cash = await cashier.get('/api/cash/current');
    expect(cash['session']['byType']['repair_payment'], 50000);
    expect(cash['session']['expectedCashCents'], 48000);

    final closed = await cashier.post('/api/cash/close', {'countedCashCents': 47500, 'keptCashCents': 10000});
    expect(closed['closed']['differenceCents'], -500);

    // الوردية الجديدة بتبدأ بالفلوس اللي اتسابت في الدرج
    cash = await cashier.get('/api/cash/current');
    expect(cash['session']['openingCashCents'], 10000);
    expect(cash['session']['expectedCashCents'], 10000);

    final sessions = await owner.get('/api/cash/sessions');
    expect((sessions['sessions'] as List).length, 2);
    await expectApiError(cashier.get('/api/cash/sessions'), 403);
  });

  test('stock adjustment is owner-only and logged', () async {
    final p = await product('جراب', qty: 5);
    await expectApiError(cashier.post('/api/products/${p['id']}/adjust', {'setQty': 1}), 403);
    await owner.post('/api/products/${p['id']}/adjust', {'setQty': 3, 'reason': 'count', 'note': 'جرد'});
    final moves = await owner.get('/api/products/${p['id']}/moves');
    expect((moves['moves'] as List).first['change'], -2);
    expect((moves['moves'] as List).first['after'], 3);
  });

  test('import from Excel rows: create, update by barcode, errors', () async {
    await product('قديم', barcode: '111', price: 1000, qty: 1);
    final res = await owner.post('/api/products/import', {
      'rows': [
        {'name': 'جديد 1', 'barcode': '222', 'priceCents': 5000, 'costCents': 3000, 'qty': 7, 'category': 'شواحن'},
        {'name': 'قديم معدل', 'barcode': '111', 'priceCents': 1500, 'qty': 4},
        {'name': '', 'barcode': '333'},
        {'name': 'من غير باركود', 'priceCents': 2000},
      ],
    });
    expect(res['created'], 2);
    expect(res['updated'], 1);
    expect((res['errors'] as List).length, 1);
    final old = (await owner.get('/api/products/lookup', query: {'barcode': '111'}))['product'];
    expect(old['name'], 'قديم معدل');
    expect(old['priceCents'], 1500);
    expect(old['qty'], 4);
  });
}
