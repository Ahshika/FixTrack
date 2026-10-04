// ignore_for_file: invalid_use_of_visible_for_testing_member
// بيرسم الشاشات الأساسية ببيانات تجريبية ويحفظها كصور PNG للمراجعة.
// التشغيل:  flutter test test_visual --update-goldens
import 'dart:io';

import 'package:fixtrack/src/core/api_client.dart';
import 'package:fixtrack/src/core/app_config.dart';
import 'package:fixtrack/src/core/models.dart';
import 'package:fixtrack/src/core/session.dart';
import 'package:fixtrack/src/core/shop.dart';
import 'package:fixtrack/src/core/theme.dart';
import 'package:fixtrack/src/core/ticket_models.dart';
import 'package:fixtrack/src/features/home/home_shell.dart';
import 'package:fixtrack/src/features/tickets/intake_screen.dart';
import 'package:fixtrack/src/features/tickets/providers.dart';
import 'package:fixtrack/src/features/tickets/ticket_detail_screen.dart';
import 'package:fixtrack/src/core/pos_models.dart';
import 'package:fixtrack/src/features/inventory/products_screen.dart';
import 'package:fixtrack/src/features/pos/cart.dart';
import 'package:fixtrack/src/features/pos/cash_screen.dart';
import 'package:fixtrack/src/features/pos/pos_screen.dart';
import 'package:fixtrack/src/features/pos/providers.dart';
import 'package:fixtrack/src/features/phones/phones_screen.dart';
import 'package:fixtrack/src/features/services/services_screen.dart';
import 'package:fixtrack/src/features/reports/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSession extends SessionController {
  @override
  Future<Session> build() async => Session(
        SessionStatus.ready,
        api: ApiClient('http://fake'),
        info: ServerInfo(serverId: 'x', setupDone: true, version: '0.1.0', api: 1, shopName: 'محل النور للصيانة', branchName: 'فرع المعادي'),
        user: AppUser(id: 'u1', name: 'أحمد حسن', username: 'ahmed', role: Role.owner, active: true),
      );
}

String _iso(Duration d) => DateTime.now().add(d).toUtc().toIso8601String();

Map<String, dynamic> _ticket(int n, String status, String brand, String model, String customer,
        {Duration? due, int paid = 50000, String? tech, List<String> problems = const ['الشاشة']}) =>
    {
      'id': 't$n',
      'number': n,
      'status': status,
      'deviceType': 'phone',
      'brand': brand,
      'model': model,
      'color': 'أسود',
      'problems': problems,
      'customerId': 'c$n',
      'customerName': customer,
      'customerPhone': '0100 123 45$n',
      'technicianId': tech == null ? null : 'u2',
      'technicianName': tech,
      'estimatedCents': 250000,
      'finalCents': null,
      'paidCents': paid,
      'dueAt': due == null ? null : _iso(due),
      'overdue': due != null && due.isNegative && !['ready', 'delivered'].contains(status),
      'createdAt': _iso(const Duration(hours: -26)),
    };

final _tickets = [
  _ticket(1004, 'repairing', 'Samsung', 'Galaxy A55', 'أحمد علي', due: const Duration(hours: -3), tech: 'محمد'),
  _ticket(1003, 'ready', 'iPhone', 'iPhone 13', 'سارة محمود', paid: 0, problems: ['البطارية']),
  _ticket(1002, 'waitingParts', 'Xiaomi', 'Redmi Note 13', 'كريم سامي', due: const Duration(days: 2), tech: 'محمد', problems: ['الشحن', 'سوفتوير']),
  _ticket(1001, 'diagnosing', 'Oppo', 'Reno 11', 'منى إبراهيم', due: const Duration(hours: 5)),
].map(Ticket.new).toList();

final _detail = TicketDetail({
  'ticket': {
    ..._tickets.first.json,
    'imei': '356789104561234',
    'problemDesc': 'الشاشة بتنور بس مفيش صورة، وقع من إيده امبارح',
    'powersOn': true,
    'conditionFlags': ['خدوش', 'شاشة مكسورة'],
    'accessories': ['جراب', 'شريحة'],
    'lockType': 'pattern',
    'hasLockSecret': true,
    'canRevealLock': true,
    'pickupPin': '4821',
    'createdByName': 'سارة',
    'approvalState': 'pending',
    'approvalCents': 320000,
    'approvalNote': 'الفلاتة كمان محتاجة تتغير',
    'publicToken': 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789',
  },
  'events': [
    {'type': 'created', 'to': 'received', 'internal': false, 'userName': 'سارة', 'createdAt': _iso(const Duration(hours: -26))},
    {'type': 'payment', 'to': '50000', 'note': 'عربون • كاش', 'userName': 'سارة', 'createdAt': _iso(const Duration(hours: -26))},
    {'type': 'assign', 'to': 'u2', 'userName': 'سارة', 'createdAt': _iso(const Duration(hours: -25))},
    {'type': 'status', 'from': 'received', 'to': 'diagnosing', 'userName': 'محمد', 'createdAt': _iso(const Duration(hours: -20))},
    {'type': 'note', 'note': 'الفلاتة سليمة، المشكلة في الشاشة نفسها', 'userName': 'محمد', 'createdAt': _iso(const Duration(hours: -19))},
    {'type': 'status', 'from': 'diagnosing', 'to': 'repairing', 'userName': 'محمد', 'createdAt': _iso(const Duration(hours: -2))},
  ],
  'payments': [
    {'amountCents': 50000, 'method': 'cash', 'kind': 'deposit', 'userName': 'سارة', 'createdAt': _iso(const Duration(hours: -26))},
  ],
});

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
    await loader.load();
  }

  await load('Cairo', 'assets/fonts/Cairo-Variable.ttf');
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'C:/src/flutter';
  await load('MaterialIcons', '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
}

Future<void> _shot(WidgetTester tester, String name, Widget home, Size size, {Brightness brightness = Brightness.light}) async {
  SharedPreferences.setMockInitialValues({'flutter.mode': 'server', 'mode': 'server'});
  final config = await AppConfig.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      appConfigProvider.overrideWithValue(config),
      sessionProvider.overrideWith(_FakeSession.new),
      ticketsProvider.overrideWith((ref, q) async => switch (q.scope) {
            'overdue' => [_tickets[0]],
            'pickup' => [_tickets[1]],
            _ => _tickets,
          }),
      ticketDetailProvider.overrideWith((ref, id) async => _detail),
      shopProvider.overrideWith((ref) async => ShopProfile({'name': 'محل النور للصيانة', 'phone': '0100 555 6677', 'receiptPaper': '80mm', 'trackingBaseUrl': 'https://fixtrack-7fcf9.web.app'})),
      dashboardProvider.overrideWith((ref) async => DashboardStats({
            'receivedToday': 3, 'inProgress': 3, 'ready': 1, 'awaitingPickup': 1, 'overdue': 1, 'deliveredToday': 2,
            'collectedTodayCents': 420000,
          })),
      staffProvider.overrideWith((ref) async => [
            StaffMember({'id': 'u1', 'name': 'أحمد حسن', 'role': 'owner'}),
            StaffMember({'id': 'u2', 'name': 'محمد', 'role': 'technician'}),
          ]),
      productsProvider.overrideWith((ref, q) async => (items: _products, count: _products.length, lowCount: 1, stockValueCents: 1845000)),
      categoriesProvider.overrideWith((ref) async => ['جرابات', 'شواحن', 'سماعات', 'اسكرينات']),
      cartProvider.overrideWith(_FakeCart.new),
      cashCurrentProvider.overrideWith((ref) async => (session: _session, categories: ['إيجار', 'كهرباء', 'أكل وشرب', 'أخرى'])),
      unitsProvider.overrideWith((ref, q) async => _units),
      walletsProvider.overrideWith((ref) async => (wallets: _wallets, todayCommissionCents: 11200)),
      reportProvider.overrideWith((ref, k) async => _report()),
      licenseProvider.overrideWith((ref) async => {'state': 'trial', 'daysLeft': 9, 'plan': 'trial', 'deviceCode': 'ABCDE-FGH23', 'devices': 3}),
      remindersProvider.overrideWith((ref) async => [Ticket({..._tickets[1].json, 'daysWaiting': 5})]),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildTheme(brightness),
      home: Consumer(builder: (context, ref, _) => ref.watch(sessionProvider).hasValue ? home : const SizedBox()),
    ),
  ));
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
}

void main() {
  setUpAll(_loadFonts);
  const desktop = Size(1280, 800);
  const phone = Size(400, 860);

  testWidgets('dashboard desktop', (t) => _shot(t, 'dashboard_desktop', const HomeShell(), desktop));
  testWidgets('dashboard phone', (t) => _shot(t, 'dashboard_phone', const HomeShell(), phone));
  testWidgets('detail desktop', (t) => _shot(t, 'detail_desktop', const TicketDetailScreen(ticketId: 't1004'), desktop));
  testWidgets('detail phone dark', (t) => _shot(t, 'detail_phone_dark', const TicketDetailScreen(ticketId: 't1004'), const Size(400, 1800), brightness: Brightness.dark));
  testWidgets('intake desktop', (t) => _shot(t, 'intake_desktop', const IntakeScreen(), const Size(1280, 1400)));
  testWidgets('intake phone', (t) => _shot(t, 'intake_phone', const IntakeScreen(), const Size(400, 2600)));
  testWidgets('pos desktop', (t) => _shot(t, 'pos_desktop', const PosScreen(), desktop));
  testWidgets('pos phone', (t) => _shot(t, 'pos_phone', const PosScreen(), phone));
  testWidgets('products desktop', (t) => _shot(t, 'products_desktop', const ProductsScreen(), desktop));
  testWidgets('cash desktop', (t) => _shot(t, 'cash_desktop', const CashScreen(), const Size(1280, 1000)));
  testWidgets('phones desktop', (t) => _shot(t, 'phones_desktop', const PhonesScreen(), desktop));
  testWidgets('wallets desktop', (t) => _shot(t, 'wallets_desktop', const ServicesScreen(), desktop));
  testWidgets('buy used desktop', (t) => _shot(t, 'buy_used_desktop', const BuyUsedScreen(), const Size(1280, 1000)));
  testWidgets('reports desktop', (t) => _shot(t, 'reports_desktop', const ReportsScreen(), const Size(1280, 1500)));
  testWidgets('reports phone', (t) => _shot(t, 'reports_phone', const ReportsScreen(), const Size(400, 1400)));
  testWidgets('shell small laptop', (t) => _shot(t, 'shell_small_laptop', const HomeShell(), const Size(1366, 640)));
}

final _products = [
  Product({'id': 'p1', 'name': 'جراب سيليكون A55 شفاف', 'barcode': '6221234567890', 'category': 'جرابات', 'costCents': 3000, 'priceCents': 7500, 'qty': 24, 'lowStock': 3, 'trackStock': true}),
  Product({'id': 'p2', 'name': 'شاحن سامسونج 25 وات أصلي', 'barcode': '8806090123456', 'category': 'شواحن', 'costCents': 28000, 'priceCents': 45000, 'qty': 2, 'lowStock': 3, 'trackStock': true}),
  Product({'id': 'p3', 'name': 'سماعة بلوتوث Lenovo LP40', 'barcode': '6970000000011', 'category': 'سماعات', 'costCents': 22000, 'priceCents': 35000, 'qty': 9, 'lowStock': 2, 'trackStock': true}),
  Product({'id': 'p4', 'name': 'اسكرينة 9D iPhone 13', 'barcode': '2012345678906', 'category': 'اسكرينات', 'costCents': 1500, 'priceCents': 5000, 'qty': 60, 'lowStock': 10, 'trackStock': true}),
  Product({'id': 'p5', 'name': 'كابل Type-C سريع 1 متر', 'barcode': null, 'category': 'شواحن', 'costCents': 2500, 'priceCents': 6000, 'qty': 0, 'lowStock': 5, 'trackStock': true}),
  Product({'id': 'p6', 'name': 'تركيب اسكرينة', 'barcode': null, 'category': null, 'costCents': 0, 'priceCents': 2000, 'qty': 0, 'lowStock': 0, 'trackStock': false}),
];

class _FakeCart extends CartController {
  @override
  CartState build() => CartState(lines: [
        CartLine(_products[0], qty: 2),
        CartLine(_products[1]),
        CartLine(_products[3], qty: 1, unitPriceCents: 4000),
      ], discountCents: 1000);
}

final _session = CashSession({
  'id': 's1',
  'openedAt': DateTime.now().subtract(const Duration(hours: 7)).toUtc().toIso8601String(),
  'openedBy': 'سارة',
  'openingCashCents': 50000,
  'byMethod': {'cash': 437000, 'vodafoneCash': 45000, 'instapay': 0, 'card': 0, 'other': 0},
  'byType': {'sale': 312000, 'repair_payment': 200000, 'expense': -30000},
  'expectedCashCents': 487000,
  'moves': [
    {'id': 'm1', 'type': 'sale', 'amountCents': 60000, 'method': 'cash', 'note': 'فاتورة #12', 'userName': 'سارة', 'createdAt': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String()},
    {'id': 'm2', 'type': 'expense', 'amountCents': -30000, 'method': 'cash', 'category': 'أكل وشرب', 'userName': 'سارة', 'createdAt': DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String()},
    {'id': 'm3', 'type': 'repair_payment', 'amountCents': 200000, 'method': 'cash', 'note': 'جهاز #1004', 'userName': 'أحمد حسن', 'createdAt': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String()},
    {'id': 'm4', 'type': 'sale', 'amountCents': 45000, 'method': 'vodafoneCash', 'note': 'فاتورة #11', 'userName': 'سارة', 'createdAt': DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String()},
  ],
});

final _units = [
  PhoneUnit({'id': 'u1', 'productId': 'p9', 'productName': 'Samsung Galaxy A55 256GB', 'imei': '490154203237518', 'condition': 'new', 'color': 'أسود', 'priceCents': 1800000, 'costCents': 1450000, 'status': 'in_stock', 'source': 'supplier'}),
  PhoneUnit({'id': 'u2', 'productId': 'p10', 'productName': 'iPhone 12 128GB', 'imei': '353918105555550', 'condition': 'used', 'color': 'أزرق', 'storage': '128GB', 'priceCents': 1100000, 'costCents': 900000, 'status': 'in_stock', 'source': 'customer', 'sellerName': 'محمد علي'}),
];

final _wallets = [
  Wallet({'id': 'w1', 'name': 'فودافون كاش', 'kind': 'vodafone', 'phone': '01001234567', 'balanceCents': 1250000, 'todayCount': 14, 'todayCommissionCents': 8500}),
  Wallet({'id': 'w2', 'name': 'إنستاباي', 'kind': 'instapay', 'balanceCents': 430000, 'todayCount': 3, 'todayCommissionCents': 1500}),
  Wallet({'id': 'w3', 'name': 'فوري', 'kind': 'fawry', 'balanceCents': 90000, 'todayCount': 6, 'todayCommissionCents': 1200}),
];

Map<String, dynamic> _report() {
  final days = [
    for (var i = 0; i < 26; i++)
      {'date': DateTime.now().subtract(Duration(days: 25 - i)).toIso8601String().substring(0, 10), 'sales': 80000 + (i * 37 % 11) * 30000, 'repairs': 50000 + (i * 53 % 7) * 40000, 'expenses': 10000},
  ];
  return {
    'netProfitCents': 3825000,
    'sales': {'count': 214, 'revenueCents': 5230000, 'costCents': 3100000, 'profitCents': 2130000, 'discountCents': 42000, 'returnsCents': 18000,
      'topProducts': [
        {'name': 'جراب سيليكون A55', 'qty': 64, 'revenue': 480000, 'profit': 288000},
        {'name': 'شاحن سامسونج 25 وات', 'qty': 21, 'revenue': 945000, 'profit': 357000},
      ], 'byCashier': []},
    'repairs': {'received': 97, 'delivered': 88, 'revenueCents': 2960000, 'partsCostCents': 1150000, 'profitCents': 1810000, 'avgHours': 31, 'warrantyReturns': 3,
      'topProblems': [{'name': 'الشاشة', 'count': 41}, {'name': 'البطارية', 'count': 22}], 'topModels': [{'name': 'Samsung A55', 'count': 12}]},
    'technicians': [
      {'name': 'محمد', 'delivered': 52, 'revenueCents': 1800000, 'partsCostCents': 700000, 'laborCents': 1100000, 'commissionCents': 220000, 'commissionType': 'percent', 'warrantyReturns': 2, 'avgHours': 28},
      {'name': 'كريم', 'delivered': 36, 'revenueCents': 1160000, 'partsCostCents': 450000, 'laborCents': 710000, 'commissionCents': 0, 'commissionType': 'none', 'warrantyReturns': 1, 'avgHours': 35},
    ],
    'services': {'commissionCents': 145000, 'byWallet': [{'name': 'فودافون كاش', 'count': 310, 'commission': 120000}]},
    'used': {'bought': 4, 'boughtCents': 3200000},
    'expenses': {'totalCents': 260000, 'byCategory': [{'name': 'إيجار', 'total': 200000}, {'name': 'كهرباء', 'total': 60000}]},
    'cashDifferenceCents': -500,
    'daily': days,
    'stock': {'valueCents': 18450000, 'deadStock': [{'name': 'جراب iPhone 8', 'qty': 14, 'value': 42000}], 'lowStock': []},
    'receivables': {'totalCents': 340000, 'customers': [{'name': 'كريم سامي', 'phone': '01112223334', 'balanceCents': 250000}]},
    'payables': {'totalCents': 1200000, 'suppliers': [{'name': 'موبي تريد', 'balanceCents': 1200000}]},
  };
}
