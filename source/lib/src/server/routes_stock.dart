part of 'api_server.dart';

/// الموردين، وفواتير الشرا، والأجهزة بالـ IMEI، وشرا الموبايلات المستعملة، والملفات (صور البطايق).
extension _StockRoutes on FixTrackServer {
  void _registerStockRoutes(Router r) {
    r.get('/api/suppliers', _authed(_listSuppliers, only: _cashStaff));
    r.post('/api/suppliers', _authed(_createSupplier, only: _cashStaff));
    r.get('/api/suppliers/<id>', _authed(_getSupplier, only: _cashStaff));
    r.patch('/api/suppliers/<id>', _authed(_updateSupplier, only: _cashStaff));
    r.post('/api/suppliers/<id>/payments', _authed(_paySupplier, only: _cashStaff));

    r.get('/api/purchases', _authed(_listPurchases, only: _cashStaff));
    r.post('/api/purchases', _authed(_createPurchase, only: _cashStaff));
    r.get('/api/purchases/<id>', _authed(_getPurchase, only: _cashStaff));

    r.get('/api/units', _authed(_listUnits));
    r.post('/api/units', _authed(_addUnits, only: _cashStaff));
    r.patch('/api/units/<id>', _authed(_updateUnit, only: _cashStaff));
    r.post('/api/units/buy-used', _authed(_buyUsed, only: _cashStaff));
    r.get('/api/imei/<imei>', _authed(_imeiHistory));

    r.post('/api/files', _authed(_uploadFile, only: _cashStaff));
    r.get('/api/files/<id>', _authed(_downloadFile, only: _cashStaff));
  }

  // ================================================================ suppliers

  int _supplierBalance(String id) {
    final bought = db.selectOne('SELECT COALESCE(SUM(total_cents), 0) AS s FROM purchases WHERE supplier_id = ?', [id])!['s'] as int;
    final paidOnInvoices = db.selectOne('SELECT COALESCE(SUM(paid_cents), 0) AS s FROM purchases WHERE supplier_id = ?', [id])!['s'] as int;
    final paid = db.selectOne('SELECT COALESCE(SUM(amount_cents), 0) AS s FROM supplier_payments WHERE supplier_id = ?', [id])!['s'] as int;
    return bought - paidOnInvoices - paid;
  }

  Map<String, Object?> _supplierJson(Map<String, Object?> s) => {
        'id': s['id'],
        'name': s['name'],
        'phone': s['phone'],
        'notes': s['notes'],
        'balanceCents': _supplierBalance(s['id'] as String),
      };

  Object? _listSuppliers(Request req, AuthUser u) {
    final rows = db.select('SELECT * FROM suppliers WHERE active = 1 ORDER BY name COLLATE NOCASE');
    return {'suppliers': rows.map(_supplierJson).toList()};
  }

  Future<Object?> _createSupplier(Request req, AuthUser u) async {
    final body = await _body(req);
    final id = _uuid.v4();
    final now = nowIso();
    db.execute(
      'INSERT INTO suppliers(id, name, phone, notes, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?)',
      [id, _requiredText(body, 'name', 'اسم المورد'), _optionalText(body, 'phone'), _optionalText(body, 'notes'), now, now],
    );
    _broadcast('suppliers');
    return {'supplier': _supplierJson(db.selectOne('SELECT * FROM suppliers WHERE id = ?', [id])!)};
  }

  Future<Object?> _updateSupplier(Request req, AuthUser u) async {
    final id = req.params['id']!;
    final s = db.selectOne('SELECT * FROM suppliers WHERE id = ?', [id]);
    if (s == null) throw ApiError(404, 'المورد ده مش موجود');
    final body = await _body(req);
    db.execute(
      'UPDATE suppliers SET name = ?, phone = ?, notes = ?, active = ?, updated_at = ? WHERE id = ?',
      [
        body.containsKey('name') ? _requiredText(body, 'name', 'اسم المورد') : s['name'],
        body.containsKey('phone') ? _optionalText(body, 'phone') : s['phone'],
        body.containsKey('notes') ? _optionalText(body, 'notes') : s['notes'],
        body['active'] == false ? 0 : 1,
        nowIso(),
        id,
      ],
    );
    _broadcast('suppliers');
    return {'supplier': _supplierJson(db.selectOne('SELECT * FROM suppliers WHERE id = ?', [id])!)};
  }

  Object? _getSupplier(Request req, AuthUser u) {
    final id = req.params['id']!;
    final s = db.selectOne('SELECT * FROM suppliers WHERE id = ?', [id]);
    if (s == null) throw ApiError(404, 'المورد ده مش موجود');
    final purchases = db.select('$_purchaseSelect WHERE p.supplier_id = ? ORDER BY p.created_at DESC LIMIT 200', [id]);
    final payments = db.select(
      'SELECT sp.*, u.name AS user_name FROM supplier_payments sp LEFT JOIN users u ON u.id = sp.user_id WHERE sp.supplier_id = ? ORDER BY sp.created_at DESC',
      [id],
    );
    return {
      'supplier': _supplierJson(s),
      'purchases': purchases.map(_purchaseSummary).toList(),
      'payments': payments
          .map((p) => {'amountCents': p['amount_cents'], 'method': p['method'], 'note': p['note'], 'userName': p['user_name'], 'createdAt': p['created_at']})
          .toList(),
    };
  }

  Future<Object?> _paySupplier(Request req, AuthUser u) async {
    final id = req.params['id']!;
    final s = db.selectOne('SELECT * FROM suppliers WHERE id = ?', [id]);
    if (s == null) throw ApiError(404, 'المورد ده مش موجود');
    final body = await _body(req);
    final amount = _cents(body['amountCents'], 'المبلغ');
    if (amount <= 0) throw ApiError(400, 'اكتب المبلغ');
    final method = PaymentMethod.parse(body['method'] as String?);
    db.transaction(() {
      db.execute(
        'INSERT INTO supplier_payments(id, supplier_id, amount_cents, method, note, user_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?)',
        [_uuid.v4(), id, amount, method.name, _optionalText(body, 'note'), u.id, nowIso()],
      );
      _cashMove('supplier_payment', -amount, method, userId: u.id, refType: 'supplier', refId: id, note: s['name'] as String);
    });
    _audit(u.id, 'supplier.payment', 'supplier', id, '${s['name']}: ${_money(amount)}');
    _broadcast('suppliers');
    _broadcast('cash');
    return {'supplier': _supplierJson(s)};
  }

  // ================================================================ purchases

  static const _purchaseSelect = '''
    SELECT p.*, s.name AS supplier_name, u.name AS user_name,
           (SELECT COALESCE(SUM(qty), 0) FROM purchase_items i WHERE i.purchase_id = p.id) AS items_count
    FROM purchases p LEFT JOIN suppliers s ON s.id = p.supplier_id LEFT JOIN users u ON u.id = p.user_id''';

  Map<String, Object?> _purchaseSummary(Map<String, Object?> p) => {
        'id': p['id'],
        'number': p['number'],
        'supplierId': p['supplier_id'],
        'supplierName': p['supplier_name'],
        'totalCents': p['total_cents'],
        'paidCents': p['paid_cents'],
        'dueCents': (p['total_cents'] as int) - (p['paid_cents'] as int),
        'itemsCount': p['items_count'],
        'note': p['note'],
        'userName': p['user_name'],
        'createdAt': p['created_at'],
      };

  Object? _listPurchases(Request req, AuthUser u) {
    final rows = db.select('$_purchaseSelect ORDER BY p.created_at DESC LIMIT 200');
    return {'purchases': rows.map(_purchaseSummary).toList()};
  }

  Object? _getPurchase(Request req, AuthUser u) {
    final p = db.selectOne('$_purchaseSelect WHERE p.id = ?', [req.params['id']]);
    if (p == null) throw ApiError(404, 'الفاتورة دي مش موجودة');
    final items = db.select('SELECT * FROM purchase_items WHERE purchase_id = ? ORDER BY rowid', [p['id']]);
    final units = db.select('SELECT product_id, imei, color, storage FROM units WHERE purchase_id = ?', [p['id']]);
    return {
      'purchase': _purchaseSummary(p),
      'items': items
          .map((i) => {
                'productId': i['product_id'],
                'name': i['name'],
                'qty': i['qty'],
                'unitCostCents': i['unit_cost_cents'],
                'imeis': units.where((x) => x['product_id'] == i['product_id']).map((x) => x['imei']).toList(),
              })
          .toList(),
    };
  }

  /// فاتورة شرا من مورد: البضاعة بتدخل المخزون، والأجهزة بتتسجل بالـ IMEI، والمدفوع بيطلع من الخزنة.
  Future<Object?> _createPurchase(Request req, AuthUser u) async {
    await _requireLicense();
    final body = await _body(req);
    final supplierId = body['supplierId'] as String?;
    if (supplierId != null && db.selectOne('SELECT id FROM suppliers WHERE id = ?', [supplierId]) == null) {
      throw ApiError(400, 'المورد ده مش موجود');
    }
    final items = body['items'];
    if (items is! List || items.isEmpty) throw ApiError(400, 'الفاتورة فاضية');
    final updateCost = body['updateCost'] != false;

    final plan = <({Map<String, Object?> product, int qty, int cost, List<Map> units})>[];
    var total = 0;
    final seenImeis = <String>{};
    for (final it in items) {
      if (it is! Map) continue;
      final p = db.selectOne('SELECT * FROM products WHERE id = ?', [it['productId']]);
      if (p == null) throw ApiError(400, 'فيه صنف مش موجود');
      final cost = _cents(it['unitCostCents'], 'سعر الشرا');
      final units = (it['units'] as List? ?? const []).whereType<Map>().toList();
      final qty = p['serialized'] == 1 ? units.length : (it['qty'] is int ? it['qty'] as int : 0);
      if (qty <= 0) throw ApiError(400, p['serialized'] == 1 ? 'سجّل الـ IMEI لكل جهاز من "${p['name']}"' : 'الكمية مش صحيحة');
      for (final unit in units) {
        final imei = _validImei(unit['imei']);
        if (!seenImeis.add(imei)) throw ApiError(400, 'الـ IMEI $imei متكرر في الفاتورة');
        if (db.selectOne("SELECT id FROM units WHERE (imei = ? OR imei2 = ?) AND status = 'in_stock'", [imei, imei]) != null) {
          throw ApiError(409, 'الجهاز $imei موجود في المخزون بالفعل');
        }
      }
      plan.add((product: p, qty: qty, cost: cost, units: units));
      total += qty * cost;
    }
    final paid = body['paidCents'] == null ? total : _cents(body['paidCents'], 'المدفوع');
    if (paid > total) throw ApiError(400, 'المدفوع أكبر من الفاتورة');
    if (paid < total && supplierId == null) throw ApiError(400, 'الشرا الآجل لازم يكون من مورد');
    final method = PaymentMethod.parse(body['method'] as String?);

    final id = _uuid.v4();
    final now = nowIso();
    final number = db.transaction(() {
      final number = db.selectOne('SELECT COALESCE(MAX(number), 0) + 1 AS n FROM purchases')!['n'] as int;
      db.execute(
        'INSERT INTO purchases(id, number, supplier_id, total_cents, paid_cents, note, user_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
        [id, number, supplierId, total, paid, _optionalText(body, 'note'), u.id, now],
      );
      for (final line in plan) {
        final p = line.product;
        db.execute(
          'INSERT INTO purchase_items(id, purchase_id, product_id, name, qty, unit_cost_cents) VALUES(?, ?, ?, ?, ?, ?)',
          [_uuid.v4(), id, p['id'], p['name'], line.qty, line.cost],
        );
        for (final unit in line.units) {
          _insertUnit(p, unit, cost: line.cost, source: 'supplier', purchaseId: id, supplierId: supplierId, userId: u.id);
        }
        _moveStock(p['id'] as String, line.qty, 'purchase', refType: 'purchase', refId: id, userId: u.id, note: 'فاتورة شرا #$number');
        if (updateCost) db.execute('UPDATE products SET cost_cents = ? WHERE id = ?', [line.cost, p['id']]);
      }
      if (paid > 0) {
        _cashMove('purchase_payment', -paid, method, userId: u.id, refType: 'purchase', refId: id, note: 'شرا #$number');
      }
      return number;
    });
    _audit(u.id, 'purchase.create', 'purchase', id, '#$number ${_money(total)}');
    _broadcast('products');
    _broadcast('units');
    _broadcast('suppliers');
    _broadcast('cash');
    return {'purchase': _purchaseSummary(db.selectOne('$_purchaseSelect WHERE p.id = ?', [id])!), 'number': number};
  }

  // ================================================================ units (IMEI)

  String _validImei(Object? raw) {
    final v = latinDigits((raw as String? ?? '').trim()).replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[0-9A-Za-z]{8,20}$').hasMatch(v)) throw ApiError(400, 'الـ IMEI أو السيريال "$raw" مش صحيح');
    return v;
  }

  /// IMEI الموبايلات 15 رقم وآخر رقم فيهم check digit (Luhn). بنستخدمه كتنبيه بس.
  bool _luhnOk(String imei) {
    if (!RegExp(r'^\d{15}$').hasMatch(imei)) return false;
    var sum = 0;
    for (var i = 0; i < 15; i++) {
      var d = int.parse(imei[14 - i]);
      if (i.isOdd) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return sum % 10 == 0;
  }

  String _insertUnit(Map<String, Object?> product, Map unit,
      {required int cost, required String source, String? purchaseId, String? supplierId, String? userId, Map<String, Object?> seller = const {}}) {
    final id = _uuid.v4();
    final now = nowIso();
    final imei2 = (unit['imei2'] as String? ?? '').trim();
    db.execute(
      'INSERT INTO units(id, product_id, imei, imei2, condition, color, storage, notes, cost_cents, price_cents, warranty_months, status, source, '
      'purchase_id, supplier_id, seller_name, seller_phone, seller_national_id, seller_id_photo, created_by, created_at, updated_at) '
      "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'in_stock', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        id, product['id'], _validImei(unit['imei']), imei2.isEmpty ? null : _validImei(imei2),
        unit['condition'] == 'used' ? 'used' : 'new',
        (unit['color'] as String?)?.trim(), (unit['storage'] as String?)?.trim(), (unit['notes'] as String?)?.trim(),
        cost, unit['priceCents'] is int ? unit['priceCents'] : null, unit['warrantyMonths'] is int ? unit['warrantyMonths'] : null,
        source, purchaseId, supplierId,
        seller['name'], seller['phone'], seller['nationalId'], seller['idPhoto'],
        userId, now, now,
      ],
    );
    return id;
  }

  Map<String, Object?> _unitJson(Map<String, Object?> x, {bool showCost = false, bool showSeller = false}) => {
        'id': x['id'],
        'productId': x['product_id'],
        'productName': x['product_name'],
        'imei': x['imei'],
        'imei2': x['imei2'],
        'condition': x['condition'],
        'color': x['color'],
        'storage': x['storage'],
        'notes': x['notes'],
        'priceCents': x['price_cents'] ?? x['product_price'],
        'warrantyMonths': x['warranty_months'] ?? x['product_warranty'],
        'status': x['status'],
        'source': x['source'],
        'createdAt': x['created_at'],
        'soldAt': x['sold_at'],
        'saleId': x['sale_id'],
        if (showCost) 'costCents': x['cost_cents'],
        if (showSeller) ...{
          'sellerName': x['seller_name'],
          'sellerPhone': x['seller_phone'],
          'sellerNationalId': x['seller_national_id'],
          'sellerIdPhoto': x['seller_id_photo'],
          'supplierName': x['supplier_name'],
        },
      };

  static const _unitSelect = '''
    SELECT x.*, p.name AS product_name, p.price_cents AS product_price, p.warranty_months AS product_warranty, s.name AS supplier_name
    FROM units x JOIN products p ON p.id = x.product_id LEFT JOIN suppliers s ON s.id = x.supplier_id''';

  Object? _listUnits(Request req, AuthUser u) {
    final qp = req.url.queryParameters;
    final where = <String>[];
    final params = <Object?>[];
    final status = qp['status'] ?? 'in_stock';
    if (status != 'all') {
      where.add('x.status = ?');
      params.add(status);
    }
    if ((qp['productId'] ?? '').isNotEmpty) {
      where.add('x.product_id = ?');
      params.add(qp['productId']);
    }
    if (qp['condition'] == 'new' || qp['condition'] == 'used') {
      where.add('x.condition = ?');
      params.add(qp['condition']);
    }
    final q = latinDigits((qp['q'] ?? '').trim());
    if (q.isNotEmpty) {
      where.add('(x.imei LIKE ? OR x.imei2 LIKE ? OR p.name LIKE ?)');
      params.addAll(['%$q%', '%$q%', '%$q%']);
    }
    final rows = db.select('$_unitSelect ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY x.created_at DESC LIMIT 300', params);
    return {'units': rows.map((x) => _unitJson(x, showCost: u.isOwner, showSeller: u.role != 'technician')).toList()};
  }

  /// إضافة أجهزة للمخزون من غير فاتورة شرا (مثلاً رصيد أول المدة).
  Future<Object?> _addUnits(Request req, AuthUser u) async {
    await _requireLicense();
    final body = await _body(req);
    final p = db.selectOne('SELECT * FROM products WHERE id = ?', [body['productId']]);
    if (p == null) throw ApiError(400, 'الصنف ده مش موجود');
    if (p['serialized'] != 1) throw ApiError(400, 'الصنف ده مش متسجل كجهاز بـ IMEI');
    final units = (body['units'] as List? ?? const []).whereType<Map>().toList();
    if (units.isEmpty) throw ApiError(400, 'سجّل IMEI جهاز واحد على الأقل');
    final cost = body['costCents'] == null ? p['cost_cents'] as int : _cents(body['costCents'], 'سعر الشرا');
    final ids = db.transaction(() {
      final ids = <String>[];
      for (final unit in units) {
        final imei = _validImei(unit['imei']);
        if (db.selectOne("SELECT id FROM units WHERE (imei = ? OR imei2 = ?) AND status = 'in_stock'", [imei, imei]) != null) {
          throw ApiError(409, 'الجهاز $imei موجود في المخزون بالفعل');
        }
        ids.add(_insertUnit(p, unit, cost: cost, source: 'manual', userId: u.id));
      }
      _moveStock(p['id'] as String, units.length, 'initial', userId: u.id, note: 'إضافة أجهزة');
      return ids;
    });
    _audit(u.id, 'unit.add', 'product', p['id'] as String, '${p['name']} × ${ids.length}');
    _broadcast('units');
    _broadcast('products');
    return {'added': ids.length};
  }

  Future<Object?> _updateUnit(Request req, AuthUser u) async {
    final id = req.params['id']!;
    final x = db.selectOne('SELECT * FROM units WHERE id = ?', [id]);
    if (x == null) throw ApiError(404, 'الجهاز ده مش موجود');
    final body = await _body(req);
    db.execute(
      'UPDATE units SET price_cents = ?, color = ?, storage = ?, notes = ?, warranty_months = ?, updated_at = ? WHERE id = ?',
      [
        body.containsKey('priceCents') ? (body['priceCents'] == null ? null : _cents(body['priceCents'], 'السعر')) : x['price_cents'],
        body.containsKey('color') ? _optionalText(body, 'color') : x['color'],
        body.containsKey('storage') ? _optionalText(body, 'storage') : x['storage'],
        body.containsKey('notes') ? _optionalText(body, 'notes') : x['notes'],
        body.containsKey('warrantyMonths') ? body['warrantyMonths'] as int? : x['warranty_months'],
        nowIso(),
        id,
      ],
    );
    _broadcast('units');
    return {'unit': _unitJson(db.selectOne('$_unitSelect WHERE x.id = ?', [id])!, showCost: u.isOwner, showSeller: true)};
  }

  /// كل حاجة البرنامج يعرفها عن IMEI: اتشرا من مين، واتباع لمين، ودخل صيانة إمتى.
  /// بتتعرض قبل شرا موبايل مستعمل عشان تحمي المحل من الأجهزة المسروقة.
  Object? _imeiHistory(Request req, AuthUser u) {
    final imei = latinDigits(req.params['imei']!.trim());
    final units = db.select(
      '$_unitSelect LEFT JOIN sales sl ON sl.id = x.sale_id WHERE x.imei = ? OR x.imei2 = ? ORDER BY x.created_at DESC',
      [imei, imei],
    );
    final tickets = db.select(
      'SELECT t.id, t.number, t.status, t.brand, t.model, t.created_at, c.name AS customer_name, c.phone AS customer_phone '
      'FROM tickets t JOIN customers c ON c.id = t.customer_id WHERE t.imei = ? ORDER BY t.created_at DESC',
      [imei],
    );
    final soldTo = <String, String?>{};
    for (final x in units.where((x) => x['sale_id'] != null)) {
      soldTo[x['id'] as String] = db.selectOne(
        'SELECT c.name FROM sales s LEFT JOIN customers c ON c.id = s.customer_id WHERE s.id = ?',
        [x['sale_id']],
      )?['name'] as String?;
    }
    return {
      'imei': imei,
      'validImei': _luhnOk(imei),
      'units': units
          .map((x) => {..._unitJson(x, showCost: u.isOwner, showSeller: u.role != 'technician'), 'soldToName': soldTo[x['id']]})
          .toList(),
      'tickets': tickets
          .map((t) => {
                'id': t['id'],
                'number': t['number'],
                'status': t['status'],
                'device': '${t['brand']} ${t['model']}',
                'customerName': t['customer_name'],
                if (u.role != 'technician') 'customerPhone': t['customer_phone'],
                'createdAt': t['created_at'],
              })
          .toList(),
    };
  }

  /// شرا موبايل مستعمل من زبون: بيانات البائع وصورة بطاقته، والفلوس بتطلع من الخزنة، والجهاز يدخل المخزون.
  Future<Object?> _buyUsed(Request req, AuthUser u) async {
    await _requireLicense();
    final body = await _body(req);
    final sellerName = _requiredText(body, 'sellerName', 'اسم البائع');
    final sellerPhone = _validPhone(body['sellerPhone']);
    final nationalId = latinDigits((body['sellerNationalId'] as String? ?? '').trim());
    if (!RegExp(r'^[23]\d{13}$').hasMatch(nationalId)) throw ApiError(400, 'الرقم القومي لازم يكون 14 رقم');
    final photo = body['idPhotoId'] as String?;
    if (photo == null || db.selectOne('SELECT id FROM files WHERE id = ?', [photo]) == null) {
      throw ApiError(400, 'لازم تصوّر بطاقة البائع');
    }
    final imei = _validImei(body['imei']);
    if (db.selectOne("SELECT id FROM units WHERE (imei = ? OR imei2 = ?) AND status = 'in_stock'", [imei, imei]) != null) {
      throw ApiError(409, 'الجهاز ده موجود في المخزون بالفعل');
    }
    final cost = _cents(body['costCents'], 'سعر الشرا');
    if (cost <= 0) throw ApiError(400, 'اكتب المبلغ اللي هتدفعه للبائع');
    final method = PaymentMethod.parse(body['method'] as String?);

    // الموديل: صنف موجود، أو صنف جديد بيتعمل (مستعمل وله IMEI)
    Map<String, Object?>? product;
    if (body['productId'] != null) {
      product = db.selectOne('SELECT * FROM products WHERE id = ?', [body['productId']]);
      if (product == null) throw ApiError(400, 'الموديل ده مش موجود');
    }
    final id = db.transaction(() {
      if (product == null) {
        final pid = _uuid.v4();
        final now = nowIso();
        db.execute(
          'INSERT INTO products(id, name, category, cost_cents, price_cents, qty, low_stock, track_stock, serialized, created_at, updated_at) '
          "VALUES(?, ?, ?, ?, ?, 0, 0, 1, 1, ?, ?)",
          [pid, _requiredText(body, 'model', 'موديل الجهاز'), 'موبايلات مستعملة', cost,
           body['priceCents'] is int ? body['priceCents'] : cost, now, now],
        );
        product = db.selectOne('SELECT * FROM products WHERE id = ?', [pid]);
      } else if (product!['serialized'] != 1) {
        db.execute('UPDATE products SET serialized = 1 WHERE id = ?', [product!['id']]);
      }
      final unitId = _insertUnit(
        product!,
        {...body, 'imei': imei, 'condition': 'used'},
        cost: cost,
        source: 'customer',
        userId: u.id,
        seller: {'name': sellerName, 'phone': sellerPhone, 'nationalId': nationalId, 'idPhoto': photo},
      );
      _moveStock(product!['id'] as String, 1, 'purchase', refType: 'unit', refId: unitId, userId: u.id, note: 'شرا مستعمل من $sellerName');
      _cashMove('used_purchase', -cost, method, userId: u.id, refType: 'unit', refId: unitId, note: '${product!['name']} من $sellerName');
      return unitId;
    });
    _audit(u.id, 'unit.buy_used', 'unit', id, '${product!['name']} • $imei • $sellerName • ${_money(cost)}');
    _broadcast('units');
    _broadcast('products');
    _broadcast('cash');
    return {'unit': _unitJson(db.selectOne('$_unitSelect WHERE x.id = ?', [id])!, showCost: true, showSeller: true), 'validImei': _luhnOk(imei)};
  }

  // ================================================================ files

  Future<Object?> _uploadFile(Request req, AuthUser u) async {
    final body = await _body(req);
    final List<int> bytes;
    try {
      bytes = base64.decode(body['data'] as String? ?? '');
    } catch (_) {
      throw ApiError(400, 'الملف مش صحيح');
    }
    if (bytes.isEmpty) throw ApiError(400, 'الملف فاضي');
    if (bytes.length > 4 * 1024 * 1024) throw ApiError(400, 'الصورة كبيرة جداً');
    final jpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
    final png = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
    if (!jpeg && !png) throw ApiError(400, 'لازم تكون صورة JPG أو PNG');
    final id = _uuid.v4();
    final dir = Directory(p.join(dataDir, 'files'))..createSync(recursive: true);
    File(p.join(dir.path, id)).writeAsBytesSync(bytes);
    db.execute(
      'INSERT INTO files(id, kind, mime, size, user_id, created_at) VALUES(?, ?, ?, ?, ?, ?)',
      [id, (body['kind'] as String? ?? 'other'), jpeg ? 'image/jpeg' : 'image/png', bytes.length, u.id, nowIso()],
    );
    return {'id': id};
  }

  Response _downloadFileResponse(String id) {
    final meta = db.selectOne('SELECT * FROM files WHERE id = ?', [id]);
    final f = File(p.join(dataDir, 'files', id));
    if (meta == null || !f.existsSync()) throw ApiError(404, 'الملف مش موجود');
    return Response.ok(f.readAsBytesSync(), headers: {'content-type': meta['mime'] as String, 'cache-control': 'private, max-age=86400'});
  }

  Object? _downloadFile(Request req, AuthUser u) => _downloadFileResponse(req.params['id']!);
}
