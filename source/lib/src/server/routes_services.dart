part of 'api_server.dart';

const walletKinds = {'vodafone', 'etisalat', 'orange', 'we', 'instapay', 'fawry', 'aman', 'other'};

/// حركات المحفظة، وأثر كل حركة على رصيد المحفظة وعلى الدرج.
/// - cash_in: العميل بيدفع كاش وإحنا بنحوّله على محفظته ← المحفظة تقل، والدرج يزيد (المبلغ + العمولة).
/// - cash_out: العميل بيحوّل لمحفظتنا وياخد كاش ← المحفظة تزيد، والدرج يقل (المبلغ − العمولة).
/// - recharge / bill: شحن رصيد أو دفع فاتورة من المحفظة ← المحفظة تقل، والدرج يزيد (المبلغ + العمولة).
/// - topup: تغذية المحفظة من الدرج ← المحفظة تزيد، والدرج يقل.
/// - withdraw: سحب من المحفظة للدرج ← المحفظة تقل، والدرج يزيد.
/// - adjust: تسوية رصيد (لصاحب المحل)، من غير أثر على الدرج.
const walletTxnTypes = {'cash_in', 'cash_out', 'recharge', 'bill', 'topup', 'withdraw', 'adjust'};

extension _ServiceRoutes on FixTrackServer {
  void _registerServiceRoutes(Router r) {
    r.get('/api/wallets', _authed(_listWallets, only: _cashStaff));
    r.post('/api/wallets', _authed(_createWallet, only: {'owner'}));
    r.patch('/api/wallets/<id>', _authed(_updateWallet, only: {'owner'}));
    r.get('/api/wallets/<id>/txns', _authed(_walletTxns, only: _cashStaff));
    r.post('/api/wallets/<id>/txns', _authed(_addWalletTxn, only: _cashStaff));
  }

  Map<String, Object?> _walletJson(Map<String, Object?> w) {
    final today = _localDayStartUtc();
    final t = db.selectOne(
      'SELECT COUNT(*) AS c, COALESCE(SUM(commission_cents), 0) AS s FROM wallet_txns WHERE wallet_id = ? AND created_at >= ?',
      [w['id'], today],
    )!;
    return {
      'id': w['id'],
      'name': w['name'],
      'kind': w['kind'],
      'phone': w['phone'],
      'balanceCents': w['balance_cents'],
      'active': w['active'] == 1,
      'todayCount': t['c'],
      'todayCommissionCents': t['s'],
    };
  }

  Object? _listWallets(Request req, AuthUser u) {
    final rows = db.select('SELECT * FROM wallets WHERE active = 1 ORDER BY created_at');
    final today = db.selectOne('SELECT COALESCE(SUM(commission_cents), 0) AS s FROM wallet_txns WHERE created_at >= ?', [_localDayStartUtc()])!;
    return {'wallets': rows.map(_walletJson).toList(), 'todayCommissionCents': today['s']};
  }

  Future<Object?> _createWallet(Request req, AuthUser u) async {
    final body = await _body(req);
    final kind = walletKinds.contains(body['kind']) ? body['kind'] as String : 'other';
    final opening = body['balanceCents'] == null ? 0 : _cents(body['balanceCents'], 'الرصيد');
    final id = _uuid.v4();
    db.transaction(() {
      db.execute(
        'INSERT INTO wallets(id, name, kind, phone, balance_cents, created_at) VALUES(?, ?, ?, ?, 0, ?)',
        [id, _requiredText(body, 'name', 'اسم المحفظة'), kind, _optionalText(body, 'phone'), nowIso()],
      );
      if (opening > 0) _walletTxn(id, 'adjust', opening, 0, u.id, note: 'رصيد أول المدة');
    });
    _audit(u.id, 'wallet.create', 'wallet', id, body['name'] as String?);
    _broadcast('wallets');
    return {'wallet': _walletJson(db.selectOne('SELECT * FROM wallets WHERE id = ?', [id])!)};
  }

  Future<Object?> _updateWallet(Request req, AuthUser u) async {
    final id = req.params['id']!;
    final w = db.selectOne('SELECT * FROM wallets WHERE id = ?', [id]);
    if (w == null) throw ApiError(404, 'المحفظة دي مش موجودة');
    final body = await _body(req);
    db.execute('UPDATE wallets SET name = ?, phone = ?, active = ? WHERE id = ?', [
      body.containsKey('name') ? _requiredText(body, 'name', 'اسم المحفظة') : w['name'],
      body.containsKey('phone') ? _optionalText(body, 'phone') : w['phone'],
      body['active'] == false ? 0 : 1,
      id,
    ]);
    _broadcast('wallets');
    return {'wallet': _walletJson(db.selectOne('SELECT * FROM wallets WHERE id = ?', [id])!)};
  }

  Object? _walletTxns(Request req, AuthUser u) {
    final rows = db.select(
      'SELECT t.*, u.name AS user_name FROM wallet_txns t LEFT JOIN users u ON u.id = t.user_id WHERE t.wallet_id = ? ORDER BY t.created_at DESC LIMIT 200',
      [req.params['id']],
    );
    return {
      'txns': rows
          .map((t) => {
                'id': t['id'],
                'type': t['type'],
                'amountCents': t['amount_cents'],
                'commissionCents': t['commission_cents'],
                'balanceAfter': t['balance_after'],
                'customerPhone': t['customer_phone'],
                'note': t['note'],
                'userName': t['user_name'],
                'createdAt': t['created_at'],
              })
          .toList(),
    };
  }

  Future<Object?> _addWalletTxn(Request req, AuthUser u) async {
    await _requireLicense();
    final id = req.params['id']!;
    final w = db.selectOne('SELECT * FROM wallets WHERE id = ? AND active = 1', [id]);
    if (w == null) throw ApiError(404, 'المحفظة دي مش موجودة');
    final body = await _body(req);
    final type = body['type'];
    if (!walletTxnTypes.contains(type)) throw ApiError(400, 'نوع العملية مش صحيح');
    if (type == 'adjust' && !u.isOwner) throw ApiError(403, 'تسوية الرصيد لصاحب المحل بس');
    final amount = type == 'adjust' ? (body['amountCents'] as int? ?? 0) : _cents(body['amountCents'], 'المبلغ');
    if (amount == 0 || (type != 'adjust' && amount < 0)) throw ApiError(400, 'اكتب المبلغ');
    final commission = body['commissionCents'] == null ? 0 : _cents(body['commissionCents'], 'العمولة');
    if (type == 'cash_out' && commission > amount) throw ApiError(400, 'العمولة أكبر من المبلغ');

    db.transaction(() => _walletTxn(id, type as String, amount, commission, u.id,
        customerPhone: _optionalText(body, 'customerPhone'), note: _optionalText(body, 'note')));
    _audit(u.id, 'wallet.$type', 'wallet', id, '${w['name']}: ${_money(amount)}${commission > 0 ? ' + عمولة ${_money(commission)}' : ''}');
    _broadcast('wallets');
    _broadcast('cash');
    return {'wallet': _walletJson(db.selectOne('SELECT * FROM wallets WHERE id = ?', [id])!)};
  }

  void _walletTxn(String walletId, String type, int amount, int commission, String? userId, {String? customerPhone, String? note}) {
    final w = db.selectOne('SELECT * FROM wallets WHERE id = ?', [walletId])!;
    final walletChange = switch (type) {
      'cash_in' || 'recharge' || 'bill' || 'withdraw' => -amount,
      'cash_out' || 'topup' => amount,
      _ => amount, // adjust
    };
    final drawerChange = switch (type) {
      'cash_in' || 'recharge' || 'bill' => amount + commission,
      'cash_out' => -(amount - commission),
      'topup' => -amount,
      'withdraw' => amount,
      _ => 0,
    };
    final after = (w['balance_cents'] as int) + walletChange;
    if (after < 0) throw ApiError(400, 'رصيد المحفظة مش كفاية (${_money(w['balance_cents'] as int)})');
    db.execute('UPDATE wallets SET balance_cents = ? WHERE id = ?', [after, walletId]);
    final txnId = _uuid.v4();
    db.execute(
      'INSERT INTO wallet_txns(id, wallet_id, type, amount_cents, commission_cents, balance_after, customer_phone, note, user_id, created_at) '
      'VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [txnId, walletId, type, amount, commission, after, customerPhone, note, userId, nowIso()],
    );
    if (drawerChange != 0) {
      _cashMove(type == 'topup' || type == 'withdraw' ? 'wallet_$type' : 'service', drawerChange, PaymentMethod.cash,
          userId: userId, refType: 'wallet', refId: txnId, category: w['name'] as String, note: _walletTxnLabel(type));
    }
  }

  String _walletTxnLabel(String type) => const {
        'cash_in': 'إيداع لعميل',
        'cash_out': 'سحب لعميل',
        'recharge': 'شحن رصيد',
        'bill': 'دفع فاتورة',
        'topup': 'تغذية المحفظة',
        'withdraw': 'سحب من المحفظة',
        'adjust': 'تسوية رصيد',
      }[type] ??
      type;
}
