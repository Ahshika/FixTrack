part of 'api_server.dart';

/// تقارير صاحب المحل: المبيعات، والصيانة، والفنيين، والخدمات، والمصروفات، والمخزون، والديون.
extension _ReportRoutes on FixTrackServer {
  void _registerReportRoutes(Router r) {
    r.get('/api/reports/summary', _authed(_reportSummary, only: {'owner'}));
  }

  Object? _reportSummary(Request req, AuthUser u) {
    final qp = req.url.queryParameters;
    final from = _validDate(qp['from']) ?? _localDayStartUtc();
    final to = _validDate(qp['to']) ?? _localDayStartUtc(1);
    return {'from': from, 'to': to, ...buildReport(from, to)};
  }

  /// بيحسب التقرير لفترة (UTC ISO). بيستخدمه كمان ملخص الفروع.
  Map<String, Object?> buildReport(String from, String to) {
    int sum(String sql, [List<Object?> params = const []]) => (db.selectOne(sql, params)!.values.first as int?) ?? 0;
    final range = [from, to];

    // ---------------- المبيعات
    final salesRow = db.selectOne(
      'SELECT COUNT(*) AS c, COALESCE(SUM(total_cents - returned_cents), 0) AS revenue, COALESCE(SUM(discount_cents), 0) AS discount, '
      'COALESCE(SUM(returned_cents), 0) AS returned FROM sales WHERE created_at >= ? AND created_at < ?',
      range,
    )!;
    final salesCost = sum(
      'SELECT COALESCE(SUM(i.cost_cents * (i.qty - i.returned_qty)), 0) FROM sale_items i JOIN sales s ON s.id = i.sale_id '
      'WHERE s.created_at >= ? AND s.created_at < ?',
      range,
    );
    final salesRevenue = salesRow['revenue'] as int;
    final topProducts = db.select(
      'SELECT i.name, SUM(i.qty - i.returned_qty) AS qty, SUM((i.qty - i.returned_qty) * i.unit_price_cents) AS revenue, '
      'SUM((i.qty - i.returned_qty) * (i.unit_price_cents - i.cost_cents)) AS profit FROM sale_items i JOIN sales s ON s.id = i.sale_id '
      'WHERE s.created_at >= ? AND s.created_at < ? GROUP BY i.product_id, i.name HAVING qty > 0 ORDER BY revenue DESC LIMIT 15',
      range,
    );
    final byCashier = db.select(
      'SELECT u.name, COUNT(*) AS count, SUM(s.total_cents - s.returned_cents) AS revenue FROM sales s LEFT JOIN users u ON u.id = s.user_id '
      'WHERE s.created_at >= ? AND s.created_at < ? GROUP BY s.user_id ORDER BY revenue DESC',
      range,
    );

    // ---------------- الصيانة (الأجهزة اللي اتسلمت في الفترة)
    final repairsRow = db.selectOne(
      "SELECT COUNT(*) AS c, COALESCE(SUM(COALESCE(final_cents, estimated_cents)), 0) AS revenue, "
      "COALESCE(AVG((julianday(delivered_at) - julianday(created_at)) * 24), 0) AS hours "
      "FROM tickets WHERE status = 'delivered' AND delivered_at >= ? AND delivered_at < ?",
      range,
    )!;
    final partsCost = sum(
      "SELECT COALESCE(SUM(p.cost_cents * p.qty), 0) FROM ticket_parts p JOIN tickets t ON t.id = p.ticket_id "
      "WHERE t.status = 'delivered' AND t.delivered_at >= ? AND t.delivered_at < ?",
      range,
    );
    final received = sum('SELECT COUNT(*) FROM tickets WHERE created_at >= ? AND created_at < ?', range);
    final warrantyReturns = sum('SELECT COUNT(*) FROM tickets WHERE warranty_of IS NOT NULL AND created_at >= ? AND created_at < ?', range);
    final problemCounts = <String, int>{};
    for (final t in db.select('SELECT problems FROM tickets WHERE created_at >= ? AND created_at < ?', range)) {
      for (final p in _jsonList(t['problems']).whereType<String>()) {
        problemCounts[p] = (problemCounts[p] ?? 0) + 1;
      }
    }
    final topProblems = (problemCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(10).map((e) => {'name': e.key, 'count': e.value}).toList();
    final topModels = db.select(
      "SELECT brand || ' ' || model AS name, COUNT(*) AS count FROM tickets WHERE created_at >= ? AND created_at < ? GROUP BY lower(brand), lower(model) ORDER BY count DESC LIMIT 10",
      range,
    );
    final repairRevenue = repairsRow['revenue'] as int;

    // ---------------- الفنيين
    final technicians = <Map<String, Object?>>[];
    for (final tech in db.select("SELECT * FROM users WHERE role IN ('technician', 'owner')")) {
      final rows = db.select(
        "SELECT t.id, COALESCE(t.final_cents, t.estimated_cents) AS revenue, t.warranty_of, "
        "(julianday(t.delivered_at) - julianday(t.created_at)) * 24 AS hours, "
        "(SELECT COALESCE(SUM(p.cost_cents * p.qty), 0) FROM ticket_parts p WHERE p.ticket_id = t.id) AS parts "
        "FROM tickets t WHERE t.technician_id = ? AND t.status = 'delivered' AND t.delivered_at >= ? AND t.delivered_at < ?",
        [tech['id'], ...range],
      );
      final returnsAgainst = sum(
        'SELECT COUNT(*) FROM tickets r JOIN tickets o ON o.id = r.warranty_of WHERE o.technician_id = ? AND r.created_at >= ? AND r.created_at < ?',
        [tech['id'], ...range],
      );
      if (rows.isEmpty && returnsAgainst == 0) continue;
      final paid = rows.where((r) => r['warranty_of'] == null).toList(); // مرتجع الضمان مالوش عمولة
      final revenue = paid.fold<int>(0, (s, r) => s + (r['revenue'] as int));
      final parts = paid.fold<int>(0, (s, r) => s + (r['parts'] as int));
      final labor = revenue - parts;
      final type = tech['commission_type'] as String? ?? 'none';
      final value = tech['commission_value'] as int? ?? 0;
      final commission = switch (type) {
        'percent' => (labor * value / 10000).round(),
        'fixed' => value * paid.length,
        _ => 0,
      };
      technicians.add({
        'id': tech['id'],
        'name': tech['name'],
        'delivered': rows.length,
        'revenueCents': revenue,
        'partsCostCents': parts,
        'laborCents': labor,
        'commissionCents': commission,
        'commissionType': type,
        'warrantyReturns': returnsAgainst,
        'avgHours': rows.isEmpty ? 0 : (rows.fold<double>(0, (s, r) => s + ((r['hours'] as num?)?.toDouble() ?? 0)) / rows.length).round(),
      });
    }
    technicians.sort((a, b) => (b['delivered'] as int).compareTo(a['delivered'] as int));

    // ---------------- الخدمات والمحافظ
    final commissions = sum('SELECT COALESCE(SUM(commission_cents), 0) FROM wallet_txns WHERE created_at >= ? AND created_at < ?', range);
    final byWallet = db.select(
      'SELECT w.name, COUNT(t.id) AS count, COALESCE(SUM(t.commission_cents), 0) AS commission FROM wallet_txns t JOIN wallets w ON w.id = t.wallet_id '
      "WHERE t.created_at >= ? AND t.created_at < ? AND t.type NOT IN ('adjust', 'topup', 'withdraw') GROUP BY w.id ORDER BY commission DESC",
      range,
    );

    // ---------------- المستعمل
    final usedBought = db.selectOne(
      "SELECT COUNT(*) AS c, COALESCE(SUM(cost_cents), 0) AS s FROM units WHERE source = 'customer' AND created_at >= ? AND created_at < ?",
      range,
    )!;

    // ---------------- المصروفات
    final expenses = -sum("SELECT COALESCE(SUM(amount_cents), 0) FROM cash_moves WHERE type = 'expense' AND created_at >= ? AND created_at < ?", range);
    final byCategory = db.select(
      "SELECT COALESCE(category, note, 'أخرى') AS name, -SUM(amount_cents) AS total FROM cash_moves WHERE type = 'expense' AND created_at >= ? AND created_at < ? "
      'GROUP BY COALESCE(category, note) ORDER BY total DESC',
      range,
    );
    final cashDiff = sum(
      'SELECT COALESCE(SUM(counted_cash_cents - expected_cash_cents), 0) FROM register_sessions WHERE closed_at >= ? AND closed_at < ? AND counted_cash_cents IS NOT NULL',
      range,
    );

    // ---------------- يوم بيوم (للرسم)
    final daily = <String, Map<String, int>>{};
    void addDaily(String sql, String key) {
      for (final r in db.select(sql, range)) {
        daily.putIfAbsent(r['d'] as String, () => {'sales': 0, 'repairs': 0, 'expenses': 0})[key] = (r['v'] as int?) ?? 0;
      }
    }

    addDaily("SELECT date(created_at, 'localtime') AS d, SUM(total_cents - returned_cents) AS v FROM sales WHERE created_at >= ? AND created_at < ? GROUP BY d", 'sales');
    addDaily(
      "SELECT date(delivered_at, 'localtime') AS d, SUM(COALESCE(final_cents, estimated_cents)) AS v FROM tickets WHERE status = 'delivered' AND delivered_at >= ? AND delivered_at < ? GROUP BY d",
      'repairs',
    );
    addDaily("SELECT date(created_at, 'localtime') AS d, -SUM(amount_cents) AS v FROM cash_moves WHERE type = 'expense' AND created_at >= ? AND created_at < ? GROUP BY d", 'expenses');

    // ---------------- المخزون والديون (دلوقتي، مش حسب الفترة)
    final stockValue = sum('SELECT COALESCE(SUM(qty * cost_cents), 0) FROM products WHERE active = 1 AND track_stock = 1 AND qty > 0 AND serialized = 0') +
        sum("SELECT COALESCE(SUM(cost_cents), 0) FROM units WHERE status = 'in_stock'");
    final deadStock = db.select(
      'SELECT p.name, p.qty, p.qty * p.cost_cents AS value FROM products p WHERE p.active = 1 AND p.track_stock = 1 AND p.qty > 0 AND p.serialized = 0 '
      'AND NOT EXISTS (SELECT 1 FROM sale_items i JOIN sales s ON s.id = i.sale_id WHERE i.product_id = p.id AND s.created_at >= ?) '
      'AND p.created_at < ? ORDER BY value DESC LIMIT 20',
      [DateTime.now().toUtc().subtract(const Duration(days: 60)).toIso8601String(), DateTime.now().toUtc().subtract(const Duration(days: 60)).toIso8601String()],
    );
    final lowStock = db.select('SELECT name, qty, low_stock FROM products WHERE active = 1 AND track_stock = 1 AND qty <= low_stock ORDER BY qty LIMIT 30');
    final debtors = <Map<String, Object?>>[];
    for (final c in db.select('SELECT id, name, phone FROM customers')) {
      final b = _customerBalance(c['id'] as String);
      if (b > 0) debtors.add({'name': c['name'], 'phone': c['phone'], 'balanceCents': b});
    }
    debtors.sort((a, b) => (b['balanceCents'] as int).compareTo(a['balanceCents'] as int));
    final suppliers = <Map<String, Object?>>[];
    for (final s in db.select('SELECT id, name FROM suppliers WHERE active = 1')) {
      final b = _supplierBalance(s['id'] as String);
      if (b > 0) suppliers.add({'name': s['name'], 'balanceCents': b});
    }

    final salesProfit = salesRevenue - salesCost;
    final repairProfit = repairRevenue - partsCost;
    return {
      'sales': {
        'count': salesRow['c'],
        'revenueCents': salesRevenue,
        'costCents': salesCost,
        'profitCents': salesProfit,
        'discountCents': salesRow['discount'],
        'returnsCents': salesRow['returned'],
        'topProducts': topProducts,
        'byCashier': byCashier,
      },
      'repairs': {
        'received': received,
        'delivered': repairsRow['c'],
        'revenueCents': repairRevenue,
        'partsCostCents': partsCost,
        'profitCents': repairProfit,
        'avgHours': ((repairsRow['hours'] as num?) ?? 0).round(),
        'warrantyReturns': warrantyReturns,
        'topProblems': topProblems,
        'topModels': topModels,
      },
      'technicians': technicians,
      'services': {'commissionCents': commissions, 'byWallet': byWallet},
      'used': {'bought': usedBought['c'], 'boughtCents': usedBought['s']},
      'expenses': {'totalCents': expenses, 'byCategory': byCategory},
      'cashDifferenceCents': cashDiff,
      'netProfitCents': salesProfit + repairProfit + commissions - expenses,
      'daily': (daily.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => {'date': e.key, ...e.value}).toList(),
      'stock': {'valueCents': stockValue, 'deadStock': deadStock, 'lowStock': lowStock},
      'receivables': {'totalCents': debtors.fold<int>(0, (s, d) => s + (d['balanceCents'] as int)), 'customers': debtors.take(30).toList()},
      'payables': {'totalCents': suppliers.fold<int>(0, (s, d) => s + (d['balanceCents'] as int)), 'suppliers': suppliers},
    };
  }
}
