import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/pos_models.dart';
import '../../core/realtime.dart';
import '../tickets/providers.dart';

typedef ProductQuery = ({String q, String? category, bool low});

final productsProvider = FutureProvider.autoDispose.family<({List<Product> items, int count, int lowCount, int? stockValueCents}), ProductQuery>(
  (ref, query) async {
    refreshOn(ref, 'products');
    final res = await apiOf(ref).get('/api/products', query: {
      if (query.q.isNotEmpty) 'q': query.q,
      'category': ?query.category,
      if (query.low) 'low': '1',
      'limit': '500',
    });
    return (
      items: (res['products'] as List).map((j) => Product(j as Map<String, dynamic>)).toList(),
      count: res['count'] as int? ?? 0,
      lowCount: res['lowCount'] as int? ?? 0,
      stockValueCents: res['stockValueCents'] as int?,
    );
  },
);

final categoriesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  refreshOn(ref, 'products');
  final res = await apiOf(ref).get('/api/products/categories');
  return (res['categories'] as List).cast<String>();
});

typedef SalesQuery = ({String q, bool dueOnly});

final salesProvider = FutureProvider.autoDispose.family<List<SaleSummary>, SalesQuery>((ref, query) async {
  refreshOn(ref, 'sales');
  final res = await apiOf(ref).get('/api/sales', query: {
    if (query.q.isNotEmpty) 'q': query.q,
    if (query.dueOnly) 'due': '1',
    'limit': '300',
  });
  return (res['sales'] as List).map((j) => SaleSummary(j as Map<String, dynamic>)).toList();
});

final saleDetailProvider = FutureProvider.autoDispose.family<SaleDetail, String>((ref, id) async {
  refreshOn(ref, 'sales');
  return SaleDetail(await apiOf(ref).get('/api/sales/$id'));
});

final cashCurrentProvider = FutureProvider.autoDispose<({CashSession session, List<String> categories})>((ref) async {
  refreshOn(ref, 'cash');
  final res = await apiOf(ref).get('/api/cash/current');
  return (
    session: CashSession(res['session'] as Map<String, dynamic>),
    categories: (res['expenseCategories'] as List).cast<String>(),
  );
});

final cashSessionsProvider = FutureProvider.autoDispose<List<CashSession>>((ref) async {
  refreshOn(ref, 'cash');
  final res = await apiOf(ref).get('/api/cash/sessions');
  return (res['sessions'] as List).map((j) => CashSession(j as Map<String, dynamic>)).toList();
});

final customerLedgerProvider = FutureProvider.autoDispose.family<({int balanceCents, List<Map<String, dynamic>> entries}), String>((ref, id) async {
  refreshOn(ref, 'customers');
  refreshOn(ref, 'sales');
  final res = await apiOf(ref).get('/api/customers/$id/ledger');
  return (balanceCents: res['balanceCents'] as int, entries: (res['entries'] as List).cast<Map<String, dynamic>>());
});

typedef UnitQuery = ({String status, String? condition, String q, String? productId});

final unitsProvider = FutureProvider.autoDispose.family<List<PhoneUnit>, UnitQuery>((ref, query) async {
  refreshOn(ref, 'units');
  final res = await apiOf(ref).get('/api/units', query: {
    'status': query.status,
    'condition': ?query.condition,
    if (query.q.isNotEmpty) 'q': query.q,
    'productId': ?query.productId,
  });
  return (res['units'] as List).map((j) => PhoneUnit(j as Map<String, dynamic>)).toList();
});

final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((ref) async {
  refreshOn(ref, 'suppliers');
  final res = await apiOf(ref).get('/api/suppliers');
  return (res['suppliers'] as List).map((j) => Supplier(j as Map<String, dynamic>)).toList();
});

final purchasesProvider = FutureProvider.autoDispose<List<PurchaseSummary>>((ref) async {
  refreshOn(ref, 'suppliers');
  final res = await apiOf(ref).get('/api/purchases');
  return (res['purchases'] as List).map((j) => PurchaseSummary(j as Map<String, dynamic>)).toList();
});

final walletsProvider = FutureProvider.autoDispose<({List<Wallet> wallets, int todayCommissionCents})>((ref) async {
  refreshOn(ref, 'wallets');
  final res = await apiOf(ref).get('/api/wallets');
  return (
    wallets: (res['wallets'] as List).map((j) => Wallet(j as Map<String, dynamic>)).toList(),
    todayCommissionCents: res['todayCommissionCents'] as int? ?? 0,
  );
});
