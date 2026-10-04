part of 'api_server.dart';

const _ticketStaff = {'owner', 'reception'};

extension _TicketRoutes on FixTrackServer {
  void _registerTicketRoutes(Router r) {
    r.get('/api/staff', _authed(_listStaff));
    r.get('/api/dashboard', _authed(_dashboard));

    r.get('/api/customers', _authed(_listCustomers, only: _ticketStaff));
    r.get('/api/customers/lookup', _authed(_lookupCustomer, only: _ticketStaff));
    r.get('/api/customers/<id>', _authed(_getCustomer, only: _ticketStaff));
    r.patch('/api/customers/<id>', _authed(_updateCustomer, only: _ticketStaff));

    r.get('/api/tickets', _authed(_listTickets));
    r.post('/api/tickets', _authed(_createTicket, only: _ticketStaff));
    r.get('/api/tickets/<id>', _authed(_getTicket));
    r.patch('/api/tickets/<id>', _authed(_updateTicket));
    r.get('/api/tickets/<id>/lock', _authed(_revealLock));
    r.post('/api/tickets/<id>/status', _authed(_changeStatus));
    r.post('/api/tickets/<id>/notes', _authed(_addNote));
    r.post('/api/tickets/<id>/payments', _authed(_addPayment, only: _ticketStaff));
    r.post('/api/tickets/<id>/deliver', _authed(_deliver, only: _ticketStaff));
  }

  SecretBox get _secrets {
    var key = db.setting('secret_key');
    if (key == null) {
      key = base64.encode(randomBytes(32));
      db.setSetting('secret_key', key);
    }
    return SecretBox(base64.decode(key));
  }

  // ---------------------------------------------------------------- staff & dashboard

  Object? _listStaff(Request req, AuthUser u) {
    final rows = db.select("SELECT id, name, role FROM users WHERE active = 1 ORDER BY role = 'technician' DESC, name");
    return {'staff': rows};
  }

  Object? _dashboard(Request req, AuthUser u) {
    final todayStart = _localDayStartUtc();
    final now = nowIso();
    final mine = u.role == 'technician' ? ' AND technician_id = ?' : '';
    final p = [if (u.role == 'technician') u.id];
    int count(String where, [List<Object?> extra = const []]) =>
        db.selectOne('SELECT COUNT(*) AS c FROM tickets WHERE $where$mine', [...extra, ...p])!['c'] as int;

    final open = _openStatuses.map((s) => "'$s'").join(',');
    final result = <String, Object?>{
      'receivedToday': count('created_at >= ?', [todayStart]),
      'inProgress': count('status IN ($open)'),
      'ready': count("status = 'ready'"),
      'awaitingPickup': count("status IN ('ready', 'cancelled', 'unrepairable')"),
      'overdue': count('status IN ($open) AND due_at IS NOT NULL AND due_at < ?', [now]),
      'deliveredToday': count("status = 'delivered' AND delivered_at >= ?", [todayStart]),
      'pickupsToday': count("status <> 'delivered' AND pickup_at >= ? AND pickup_at < ?", [todayStart, _localDayStartUtc(1)]),
    };
    if (u.role != 'technician') {
      final sales = db.selectOne(
        'SELECT COUNT(*) AS c, COALESCE(SUM(total_cents - returned_cents), 0) AS s FROM sales WHERE created_at >= ?',
        [todayStart],
      )!;
      result['salesTodayCount'] = sales['c'];
      result['salesTodayCents'] = sales['s'];
      result['lowStockCount'] = db.selectOne('SELECT COUNT(*) AS c FROM products WHERE active = 1 AND track_stock = 1 AND qty <= low_stock')!['c'];
    }
    if (u.isOwner) {
      result['collectedTodayCents'] =
          db.selectOne('SELECT COALESCE(SUM(amount_cents), 0) AS s FROM payments WHERE created_at >= ?', [todayStart])!['s'];
    }
    return result;
  }

  String _localDayStartUtc([int addDays = 0]) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + addDays).toUtc().toIso8601String();
  }

  List<String> get _openStatuses => TicketStatus.values.where((s) => s.isOpen).map((s) => s.name).toList();

  // ---------------------------------------------------------------- customers

  Object? _listCustomers(Request req, AuthUser u) {
    final q = (req.url.queryParameters['q'] ?? '').trim();
    final limit = (int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 50).clamp(1, 200);
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '') ?? 0;
    final where = <String>[];
    final params = <Object?>[];
    if (q.isNotEmpty) {
      final phone = normalizePhone(q);
      where.add('(c.name LIKE ?${phone.length >= 3 ? ' OR c.phone_norm LIKE ?' : ''})');
      params.add('%$q%');
      if (phone.length >= 3) params.add('%$phone%');
    }
    final rows = db.select(
      'SELECT c.*, COUNT(t.id) AS tickets_count, MAX(t.created_at) AS last_visit '
      'FROM customers c LEFT JOIN tickets t ON t.customer_id = c.id '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'GROUP BY c.id ORDER BY COALESCE(MAX(t.created_at), c.created_at) DESC LIMIT ? OFFSET ?',
      [...params, limit, offset],
    );
    return {'customers': rows.map((r) => {..._customerJson(r), 'balanceCents': _customerBalance(r['id'] as String)}).toList()};
  }

  Object? _lookupCustomer(Request req, AuthUser u) {
    final phone = normalizePhone(req.url.queryParameters['phone'] ?? '');
    if (phone.length < 6) return {'customer': null};
    final row = db.selectOne(
      'SELECT c.*, (SELECT COUNT(*) FROM tickets t WHERE t.customer_id = c.id) AS tickets_count, '
      '(SELECT MAX(created_at) FROM tickets t WHERE t.customer_id = c.id) AS last_visit '
      'FROM customers c WHERE c.phone_norm = ? ORDER BY c.updated_at DESC LIMIT 1',
      [phone],
    );
    return {'customer': row == null ? null : _customerJson(row)};
  }

  Object? _getCustomer(Request req, AuthUser u) {
    final row = db.selectOne('SELECT * FROM customers WHERE id = ?', [req.params['id']]);
    if (row == null) throw ApiError(404, 'العميل ده مش موجود');
    final tickets = db.select('$_ticketSelect WHERE t.customer_id = ? ORDER BY t.created_at DESC', [row['id']]);
    return {
      'customer': {..._customerJson(row), 'balanceCents': _customerBalance(row['id'] as String)},
      'tickets': tickets.map(_ticketSummary).toList(),
    };
  }

  Future<Object?> _updateCustomer(Request req, AuthUser u) async {
    final id = req.params['id']!;
    final row = db.selectOne('SELECT * FROM customers WHERE id = ?', [id]);
    if (row == null) throw ApiError(404, 'العميل ده مش موجود');
    final body = await _body(req);
    final name = body.containsKey('name') ? _requiredText(body, 'name', 'اسم العميل') : row['name'] as String;
    final phone = body.containsKey('phone') ? _validPhone(body['phone']) : row['phone'] as String;
    final whatsapp = body.containsKey('whatsapp') ? _optionalText(body, 'whatsapp') : row['whatsapp'] as String?;
    final notes = body.containsKey('notes') ? _optionalText(body, 'notes') : row['notes'] as String?;
    db.execute(
      'UPDATE customers SET name = ?, phone = ?, phone_norm = ?, whatsapp = ?, notes = ?, updated_at = ? WHERE id = ?',
      [name, phone, normalizePhone(phone), whatsapp, notes, nowIso(), id],
    );
    _audit(u.id, 'customer.update', 'customer', id, name);
    _broadcast('customers');
    _broadcast('tickets');
    return {'customer': _customerJson(db.selectOne('SELECT * FROM customers WHERE id = ?', [id])!)};
  }

  Map<String, Object?> _customerJson(Map<String, Object?> r) => {
        'id': r['id'],
        'name': r['name'],
        'phone': r['phone'],
        'whatsapp': r['whatsapp'],
        'notes': r['notes'],
        'createdAt': r['created_at'],
        if (r.containsKey('tickets_count')) 'ticketsCount': r['tickets_count'],
        if (r.containsKey('last_visit')) 'lastVisit': r['last_visit'],
      };

  String _validPhone(Object? raw) {
    final v = (raw as String? ?? '').trim();
    final digits = normalizePhone(v);
    if (digits.length < 6 || digits.length > 15) throw ApiError(400, 'رقم التليفون مش صحيح');
    return v;
  }

  // ---------------------------------------------------------------- tickets: read

  static const _ticketSelect = '''
    SELECT t.*, c.name AS customer_name, c.phone AS customer_phone, c.whatsapp AS customer_whatsapp,
           tech.name AS technician_name,
           (SELECT COALESCE(SUM(amount_cents), 0) FROM payments p WHERE p.ticket_id = t.id) AS paid_cents
    FROM tickets t
    JOIN customers c ON c.id = t.customer_id
    LEFT JOIN users tech ON tech.id = t.technician_id''';

  Map<String, Object?> _ticketSummary(Map<String, Object?> r) {
    final status = TicketStatus.parse(r['status'] as String?);
    final due = r['due_at'] as String?;
    return {
      'id': r['id'],
      'number': r['number'],
      'status': status.name,
      'deviceType': r['device_type'],
      'brand': r['brand'],
      'model': r['model'],
      'color': r['color'],
      'problems': _jsonList(r['problems']),
      'customerId': r['customer_id'],
      'customerName': r['customer_name'],
      'customerPhone': r['customer_phone'],
      'technicianId': r['technician_id'],
      'technicianName': r['technician_name'],
      'estimatedCents': r['estimated_cents'],
      'finalCents': r['final_cents'],
      'paidCents': r['paid_cents'],
      'dueAt': due,
      'overdue': status.isOpen && due != null && due.compareTo(nowIso()) < 0,
      'createdAt': r['created_at'],
      'updatedAt': r['updated_at'],
      'deliveredAt': r['delivered_at'],
      'approvalState': r['approval_state'],
      'approvalCents': r['approval_cents'],
      'approvalNote': r['approval_note'],
      'pickupAt': r['pickup_at'],
      'warrantyDays': r['warranty_days'],
      'warrantyUntil': r['warranty_until'],
      'warrantyOf': r['warranty_of'],
      'readyAt': r['ready_at'],
    };
  }

  List<Object?> _jsonList(Object? raw) {
    if (raw is! String) return const [];
    try {
      final v = jsonDecode(raw);
      return v is List ? v : const [];
    } catch (_) {
      return const [];
    }
  }

  Object? _listTickets(Request req, AuthUser u) {
    final qp = req.url.queryParameters;
    final q = (qp['q'] ?? '').trim();
    final scope = qp['scope'] ?? 'active';
    final limit = (int.tryParse(qp['limit'] ?? '') ?? 50).clamp(1, 200);
    final offset = int.tryParse(qp['offset'] ?? '') ?? 0;

    final where = <String>[];
    final params = <Object?>[];
    final open = _openStatuses.map((s) => "'$s'").join(',');
    switch (scope) {
      case 'all':
        break;
      case 'active':
        where.add("t.status <> 'delivered'");
      case 'open':
        where.add('t.status IN ($open)');
      case 'pickup':
        where.add("t.status IN ('ready', 'cancelled', 'unrepairable')");
      case 'pickupToday':
        where.add("t.status <> 'delivered' AND t.pickup_at >= ? AND t.pickup_at < ?");
        params.addAll([_localDayStartUtc(), _localDayStartUtc(1)]);
      case 'overdue':
        where.add('t.status IN ($open) AND t.due_at IS NOT NULL AND t.due_at < ?');
        params.add(nowIso());
      default:
        if (TicketStatus.tryParse(scope) == null) throw ApiError(400, 'فلتر مش معروف');
        where.add('t.status = ?');
        params.add(scope);
    }
    if (u.role == 'technician') {
      where.add('t.technician_id = ?');
      params.add(u.id);
    }
    // مسح QR الوصل بيكتب لينك التتبع في خانة البحث (سكانر USB أو كاميرا)
    final tokenMatch = RegExp(r'/t/([A-Za-z0-9_-]{20,})').firstMatch(q);
    final token = tokenMatch?.group(1) ?? (RegExp(r'^[A-Za-z0-9_-]{40,}$').hasMatch(q) ? q : null);
    if (token != null) {
      where.add('t.public_token = ?');
      params.add(token);
    } else if (q.isNotEmpty) {
      final parts = <String>['c.name LIKE ?', 't.model LIKE ?', 't.brand LIKE ?', 't.imei LIKE ?'];
      params.addAll(['%$q%', '%$q%', '%$q%', '%$q%']);
      final phone = normalizePhone(q);
      if (phone.length >= 3) {
        parts.add('c.phone_norm LIKE ?');
        params.add('%$phone%');
      }
      final number = int.tryParse(phone);
      if (number != null && phone.length <= 7) {
        parts.add('t.number = ?');
        params.add(number);
      }
      where.add('(${parts.join(' OR ')})');
    }

    final order = switch (scope) {
      'pickup' || 'ready' => 't.updated_at DESC',
      'pickupToday' => 't.pickup_at',
      'open' || 'overdue' => 'CASE WHEN t.due_at IS NULL THEN 1 ELSE 0 END, t.due_at, t.created_at',
      _ => 't.created_at DESC',
    };
    final rows = db.select(
      '$_ticketSelect ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY $order LIMIT ? OFFSET ?',
      [...params, limit, offset],
    );
    return {'tickets': rows.map(_ticketSummary).toList()};
  }

  Map<String, Object?> _loadTicket(String id, AuthUser u) {
    final row = db.selectOne('$_ticketSelect WHERE t.id = ?', [id]);
    if (row == null) throw ApiError(404, 'الجهاز ده مش موجود');
    if (u.role == 'technician' && row['technician_id'] != u.id) {
      throw ApiError(403, 'الجهاز ده مش متسلملك');
    }
    return row;
  }

  Object? _getTicket(Request req, AuthUser u) => _ticketDetail(_loadTicket(req.params['id']!, u), u);

  Map<String, Object?> _ticketDetail(Map<String, Object?> r, AuthUser u) {
    final events = db.select(
      'SELECT e.*, u.name AS user_name FROM ticket_events e LEFT JOIN users u ON u.id = e.user_id '
      'WHERE e.ticket_id = ? ORDER BY e.id',
      [r['id']],
    );
    final payments = db.select(
      'SELECT p.*, u.name AS user_name FROM payments p LEFT JOIN users u ON u.id = p.user_id '
      'WHERE p.ticket_id = ? ORDER BY p.created_at',
      [r['id']],
    );
    String? userName(Object? id) =>
        id == null ? null : db.selectOne('SELECT name FROM users WHERE id = ?', [id])?['name'] as String?;

    return {
      'ticket': {
        ..._ticketSummary(r),
        'imei': r['imei'],
        'problemDesc': r['problem_desc'],
        'powersOn': r['powers_on'] == null ? null : r['powers_on'] == 1,
        'conditionFlags': _jsonList(r['condition_flags']),
        'conditionNotes': r['condition_notes'],
        'accessories': _jsonList(r['accessories']),
        'lockType': r['lock_type'],
        'hasLockSecret': r['lock_secret'] != null,
        'canRevealLock': r['lock_secret'] != null && (u.isOwner || r['technician_id'] == u.id),
        if (u.role != 'technician') 'pickupPin': r['pickup_pin'],
        'publicToken': r['public_token'],
        'customerWhatsapp': r['customer_whatsapp'],
        'createdByName': userName(r['created_by']),
        'deliveredByName': userName(r['delivered_by']),
      },
      'events': events
          .map((e) => {
                'id': e['id'],
                'type': e['type'],
                'from': e['from_value'],
                'to': e['to_value'],
                'note': e['note'],
                'internal': e['internal'] == 1,
                'userName': e['user_name'],
                'createdAt': e['created_at'],
              })
          .toList(),
      'payments': payments
          .map((p) => {
                'id': p['id'],
                'amountCents': p['amount_cents'],
                'method': p['method'],
                'kind': p['kind'],
                'note': p['note'],
                'userName': p['user_name'],
                'createdAt': p['created_at'],
              })
          .toList(),
      'messages': _ticketMessages(r['id'] as String),
      'parts': _ticketParts(r['id'] as String, showCost: u.isOwner),
      if (r['warranty_of'] != null)
        'warrantyOrigin': db.selectOne('SELECT id, number, delivered_at, warranty_until FROM tickets WHERE id = ?', [r['warranty_of']]),
      'warrantyReturns': db
          .select('SELECT id, number, created_at FROM tickets WHERE warranty_of = ? ORDER BY created_at', [r['id']])
          .map((w) => {'id': w['id'], 'number': w['number'], 'createdAt': w['created_at']})
          .toList(),
    };
  }

  Object? _revealLock(Request req, AuthUser u) {
    final r = _loadTicket(req.params['id']!, u);
    if (!(u.isOwner || r['technician_id'] == u.id)) {
      throw ApiError(403, 'رمز فتح الشاشة بيظهر للفني المسؤول وصاحب المحل بس');
    }
    final sealed = r['lock_secret'] as String?;
    if (sealed == null) throw ApiError(404, 'مفيش رمز متسجل للجهاز ده');
    final secret = _secrets.open(sealed);
    if (secret == null) throw ApiError(500, 'مش قادر أفك تشفير الرمز');
    _audit(u.id, 'ticket.lock_view', 'ticket', r['id'] as String, '#${r['number']}');
    return {'lockType': r['lock_type'], 'secret': secret};
  }

  // ---------------------------------------------------------------- tickets: write

  Future<Object?> _createTicket(Request req, AuthUser u) async {
    await _requireLicense();
    final body = await _body(req);
    final customer = body['customer'];
    if (customer is! Map<String, dynamic>) throw ApiError(400, 'بيانات العميل ناقصة');

    final brand = _requiredText(body, 'brand', 'ماركة الجهاز');
    final model = _requiredText(body, 'model', 'موديل الجهاز');
    final problems = _stringList(body['problems']);
    final problemDesc = _optionalText(body, 'problemDesc');
    if (problems.isEmpty && problemDesc == null) throw ApiError(400, 'لازم تحدد المشكلة');
    final lockType = LockType.parse(body['lockType'] as String?);
    final lockSecret = _optionalText(body, 'lockSecret');
    final estimated = body['estimatedCents'] == null ? 0 : _cents(body['estimatedCents'], 'التكلفة');
    final technicianId = _validTechnician(body['technicianId']);
    final dueAt = _validDate(body['dueAt']);
    final deposit = body['depositCents'] == null ? 0 : _cents(body['depositCents'], 'العربون');
    final depositMethod = PaymentMethod.parse(body['depositMethod'] as String?);

    final now = nowIso();
    final ticketId = _uuid.v4();
    final branchId = db.selectOne('SELECT id FROM branches WHERE is_local = 1 LIMIT 1')?['id'];

    final number = db.transaction(() {
      // العميل: موجود ولا جديد
      String customerId;
      final existingId = customer['id'] as String?;
      if (existingId != null) {
        if (db.selectOne('SELECT id FROM customers WHERE id = ?', [existingId]) == null) {
          throw ApiError(400, 'العميل ده مش موجود');
        }
        customerId = existingId;
        final updates = <String, Object?>{};
        if (customer['name'] is String && (customer['name'] as String).trim().isNotEmpty) {
          updates['name'] = (customer['name'] as String).trim();
        }
        if (customer['whatsapp'] is String) updates['whatsapp'] = _optionalText(customer, 'whatsapp');
        if (updates.isNotEmpty) {
          db.execute(
            'UPDATE customers SET ${updates.keys.map((k) => '$k = ?').join(', ')}, updated_at = ? WHERE id = ?',
            [...updates.values, now, customerId],
          );
        }
      } else {
        final name = _requiredText(customer, 'name', 'اسم العميل');
        final phone = _validPhone(customer['phone']);
        customerId = _uuid.v4();
        db.execute(
          'INSERT INTO customers(id, name, phone, phone_norm, whatsapp, notes, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
          [customerId, name, phone, normalizePhone(phone), _optionalText(customer, 'whatsapp'), null, now, now],
        );
      }

      final number = (db.selectOne('SELECT COALESCE(MAX(number), 1000) + 1 AS n FROM tickets')!['n'] as int);
      db.execute(
        'INSERT INTO tickets(id, number, branch_id, customer_id, device_type, brand, model, color, imei, problems, '
        'problem_desc, powers_on, condition_flags, condition_notes, accessories, lock_type, lock_secret, '
        'estimated_cents, due_at, technician_id, status, pickup_pin, public_token, created_by, created_at, updated_at) '
        'VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          ticketId, number, branchId, customerId,
          _deviceType(body['deviceType']), brand, model,
          _optionalText(body, 'color'), _optionalText(body, 'imei'),
          jsonEncode(problems), problemDesc,
          body['powersOn'] == null ? null : (body['powersOn'] == true ? 1 : 0),
          jsonEncode(_stringList(body['conditionFlags'])), _optionalText(body, 'conditionNotes'),
          jsonEncode(_stringList(body['accessories'])),
          lockSecret == null ? 'none' : lockType.name,
          lockSecret == null ? null : _secrets.seal(lockSecret),
          estimated, dueAt, technicianId,
          TicketStatus.received.name, _randomPin(), randomToken(),
          u.id, now, now,
        ],
      );
      _event(ticketId, 'created', to: TicketStatus.received.name, userId: u.id, internal: false);
      if (body['warrantyOf'] is String) {
        final origin = _validWarrantyOrigin(body['warrantyOf'] as String, customerId, _optionalText(body, 'imei'));
        db.execute('UPDATE tickets SET warranty_of = ? WHERE id = ?', [origin['id'], ticketId]);
        _event(ticketId, 'warranty_return', to: '${origin['number']}', userId: u.id,
            note: 'مرتجع ضمان من جهاز #${origin['number']}');
      }
      if (technicianId != null) _event(ticketId, 'assign', to: technicianId, userId: u.id);
      if (deposit > 0) {
        _insertPayment(ticketId, deposit, depositMethod, PaymentKind.deposit, null, u.id);
      }
      return number;
    });

    _audit(u.id, 'ticket.create', 'ticket', ticketId, '#$number $brand $model');
    _autoMessage(ticketId, MessageEvent.received);
    _broadcast('tickets');
    _broadcast('customers');
    return _ticketDetail(_loadTicket(ticketId, u), u);
  }

  Future<Object?> _updateTicket(Request req, AuthUser u) async {
    final r = _loadTicket(req.params['id']!, u);
    final id = r['id'] as String;
    if (r['status'] == 'delivered' && !u.isOwner) throw ApiError(400, 'الجهاز اتسلم خلاص، التعديل لصاحب المحل بس');
    final body = await _body(req);

    final isTech = u.role == 'technician';
    const techAllowed = {'dueAt'};
    if (isTech && body.keys.any((k) => !techAllowed.contains(k))) {
      throw ApiError(403, 'الفني يقدر يعدل الموعد المتوقع بس. أي تعديل تاني من الاستقبال');
    }

    final sets = <String, Object?>{};
    final events = <void Function()>[];

    void textField(String key, String column, {bool required = false, String? label}) {
      if (!body.containsKey(key)) return;
      sets[column] = required ? _requiredText(body, key, label ?? key) : _optionalText(body, key);
    }

    textField('brand', 'brand', required: true, label: 'ماركة الجهاز');
    textField('model', 'model', required: true, label: 'موديل الجهاز');
    textField('color', 'color');
    textField('imei', 'imei');
    textField('problemDesc', 'problem_desc');
    textField('conditionNotes', 'condition_notes');
    if (body.containsKey('deviceType')) sets['device_type'] = _deviceType(body['deviceType']);
    if (body.containsKey('problems')) sets['problems'] = jsonEncode(_stringList(body['problems']));
    if (body.containsKey('conditionFlags')) sets['condition_flags'] = jsonEncode(_stringList(body['conditionFlags']));
    if (body.containsKey('accessories')) sets['accessories'] = jsonEncode(_stringList(body['accessories']));
    if (body.containsKey('powersOn')) sets['powers_on'] = body['powersOn'] == null ? null : (body['powersOn'] == true ? 1 : 0);
    if (body.containsKey('lockSecret')) {
      final secret = _optionalText(body, 'lockSecret');
      sets['lock_secret'] = secret == null ? null : _secrets.seal(secret);
      sets['lock_type'] = secret == null ? 'none' : LockType.parse(body['lockType'] as String?).name;
    }

    if (body.containsKey('estimatedCents')) {
      final v = _cents(body['estimatedCents'], 'التكلفة');
      if (v != r['estimated_cents']) {
        sets['estimated_cents'] = v;
        events.add(() => _event(id, 'estimate', from: '${r['estimated_cents']}', to: '$v', userId: u.id));
      }
    }
    if (body.containsKey('finalCents')) {
      final v = body['finalCents'] == null ? null : _cents(body['finalCents'], 'التكلفة النهائية');
      if (v != r['final_cents']) {
        sets['final_cents'] = v;
        events.add(() => _event(id, 'final_cost', from: r['final_cents']?.toString(), to: v?.toString(), userId: u.id));
      }
    }
    if (body.containsKey('dueAt')) {
      final v = _validDate(body['dueAt']);
      if (v != r['due_at']) {
        sets['due_at'] = v;
        events.add(() => _event(id, 'due', from: r['due_at'] as String?, to: v, userId: u.id, internal: false));
      }
    }
    if (body.containsKey('technicianId')) {
      final v = _validTechnician(body['technicianId']);
      if (v != r['technician_id']) {
        sets['technician_id'] = v;
        events.add(() => _event(id, 'assign', from: r['technician_id'] as String?, to: v, userId: u.id));
      }
    }

    if (sets.isEmpty) return _ticketDetail(r, u);
    final detailsChanged = sets.keys.any((k) => !{'estimated_cents', 'final_cents', 'due_at', 'technician_id'}.contains(k));
    db.transaction(() {
      db.execute(
        'UPDATE tickets SET ${sets.keys.map((k) => '$k = ?').join(', ')}, updated_at = ? WHERE id = ?',
        [...sets.values, nowIso(), id],
      );
      for (final e in events) {
        e();
      }
      if (detailsChanged) _event(id, 'edit', userId: u.id);
    });
    if (sets['due_at'] != null) _autoMessage(id, MessageEvent.dueChanged);
    _audit(u.id, 'ticket.update', 'ticket', id, '#${r['number']}');
    _broadcast('tickets');
    return _ticketDetail(_loadTicket(id, u), u);
  }

  Future<Object?> _changeStatus(Request req, AuthUser u) async {
    final r = _loadTicket(req.params['id']!, u);
    final id = r['id'] as String;
    final body = await _body(req);
    final to = TicketStatus.tryParse(body['status'] as String?);
    if (to == null) throw ApiError(400, 'المرحلة مش صحيحة');
    if (to == TicketStatus.delivered) throw ApiError(400, 'التسليم بيتم من زرار "تسليم للعميل"');
    final from = TicketStatus.parse(r['status'] as String?);
    if (from == TicketStatus.delivered) throw ApiError(400, 'الجهاز اتسلم خلاص');
    if (from == to) return _ticketDetail(r, u);

    db.transaction(() {
      db.execute('UPDATE tickets SET status = ?, updated_at = ? WHERE id = ?', [to.name, nowIso(), id]);
      _event(id, 'status', from: from.name, to: to.name, note: _optionalText(body, 'note'), userId: u.id, internal: false);
      _onStatusChanged(id, from, to);
    });
    final event = MessageEvent.forStatus(to);
    if (event != null) _autoMessage(id, event);
    _audit(u.id, 'ticket.status', 'ticket', id, '#${r['number']}: من ${from.label} لـ ${to.label}');
    _broadcast('tickets');
    return _ticketDetail(_loadTicket(id, u), u);
  }

  Future<Object?> _addNote(Request req, AuthUser u) async {
    final r = _loadTicket(req.params['id']!, u);
    final body = await _body(req);
    final note = _requiredText(body, 'note', 'الملاحظة');
    db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [nowIso(), r['id']]);
    _event(r['id'] as String, 'note', note: note, userId: u.id, internal: body['internal'] != false);
    _broadcast('tickets');
    return _ticketDetail(_loadTicket(r['id'] as String, u), u);
  }

  Future<Object?> _addPayment(Request req, AuthUser u) async {
    final r = _loadTicket(req.params['id']!, u);
    final body = await _body(req);
    final kind = PaymentKind.parse(body['kind'] as String?);
    final amount = _cents(body['amountCents'], 'المبلغ');
    if (amount == 0) throw ApiError(400, 'اكتب المبلغ');
    final method = PaymentMethod.parse(body['method'] as String?);
    if (kind == PaymentKind.refund && amount > (r['paid_cents'] as int)) {
      throw ApiError(400, 'المرتجع أكبر من اللي العميل دفعه');
    }
    db.transaction(() {
      _insertPayment(r['id'] as String, amount, method, kind, _optionalText(body, 'note'), u.id);
      db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [nowIso(), r['id']]);
    });
    _audit(u.id, 'payment.create', 'ticket', r['id'] as String, '#${r['number']} ${kind.label} ${amount / 100}');
    _broadcast('tickets');
    return _ticketDetail(_loadTicket(r['id'] as String, u), u);
  }

  Future<Object?> _deliver(Request req, AuthUser u) async {
    final r = _loadTicket(req.params['id']!, u);
    final id = r['id'] as String;
    if (r['status'] == 'delivered') throw ApiError(400, 'الجهاز اتسلم قبل كده');
    final body = await _body(req);

    final override = body['override'] == true;
    if (override) {
      if (!u.isOwner) throw ApiError(403, 'التسليم من غير كود الاستلام لصاحب المحل بس');
    } else if ((body['pin'] as String? ?? '').trim() != r['pickup_pin']) {
      throw ApiError(400, 'كود الاستلام غلط. الكود مكتوب في وصل العميل');
    }

    final finalCents = body.containsKey('finalCents') && body['finalCents'] != null
        ? _cents(body['finalCents'], 'التكلفة النهائية')
        : (r['final_cents'] as int?) ?? (r['estimated_cents'] as int);
    final payNow = body['paymentCents'] == null ? 0 : _cents(body['paymentCents'], 'المبلغ');
    final method = PaymentMethod.parse(body['paymentMethod'] as String?);
    final remaining = finalCents - (r['paid_cents'] as int) - payNow;
    if (payNow > 0 && remaining < 0) throw ApiError(400, 'المبلغ أكبر من الباقي على العميل');
    if (remaining > 0 && body['allowDebt'] != true) {
      throw ApiError(400, 'لسه فيه باقي ${_money(remaining)} على العميل');
    }

    // مرتجع الضمان مالوش ضمان جديد؛ الضمان الأصلي هو اللي ماشي
    final warrantyDays = r['warranty_of'] != null
        ? 0
        : body['warrantyDays'] is int
            ? (body['warrantyDays'] as int).clamp(0, 365)
            : _defaultWarrantyDays;
    final now = nowIso();
    db.transaction(() {
      if (payNow > 0) _insertPayment(id, payNow, method, PaymentKind.payment, null, u.id);
      db.execute(
        "UPDATE tickets SET status = 'delivered', final_cents = ?, delivered_at = ?, delivered_by = ?, "
        'lock_secret = NULL, warranty_days = ?, warranty_until = ?, ready_at = NULL, updated_at = ? WHERE id = ?',
        [finalCents, now, u.id, warrantyDays, warrantyDays > 0 ? DateTime.now().toUtc().add(Duration(days: warrantyDays)).toIso8601String() : null, now, id],
      );
      _event(id, 'status', from: r['status'] as String, to: 'delivered', userId: u.id, internal: false,
          note: [
            if (override) 'تسليم بدون كود الاستلام',
            if (remaining > 0) 'باقي على العميل ${_money(remaining)}',
          ].join(' • ').emptyToNull);
    });
    _autoMessage(id, MessageEvent.delivered);
    _audit(u.id, 'ticket.deliver', 'ticket', id, '#${r['number']}${override ? ' (بدون كود)' : ''}');
    _broadcast('tickets');
    return _ticketDetail(_loadTicket(id, u), u);
  }

  // ---------------------------------------------------------------- helpers

  void _event(String ticketId, String type,
      {String? from, String? to, String? note, String? userId, bool internal = true}) {
    db.execute(
      'INSERT INTO ticket_events(ticket_id, type, from_value, to_value, note, internal, user_id, created_at) '
      'VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
      [ticketId, type, from, to, note, internal ? 1 : 0, userId, nowIso()],
    );
  }

  void _insertPayment(String ticketId, int amount, PaymentMethod method, PaymentKind kind, String? note, String userId) {
    db.execute(
      'INSERT INTO payments(id, ticket_id, amount_cents, method, kind, note, user_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
      [_uuid.v4(), ticketId, kind == PaymentKind.refund ? -amount : amount, method.name, kind.name, note, userId, nowIso()],
    );
    final number = db.selectOne('SELECT number FROM tickets WHERE id = ?', [ticketId])?['number'];
    _cashMove(kind == PaymentKind.refund ? 'repair_refund' : 'repair_payment', kind == PaymentKind.refund ? -amount : amount, method,
        userId: userId, refType: 'ticket', refId: ticketId, note: 'جهاز #$number');
    _event(ticketId, 'payment', to: '${kind == PaymentKind.refund ? -amount : amount}', note: '${kind.label} • ${method.label}', userId: userId);
  }

  int _cents(Object? raw, String label) {
    final v = raw is int ? raw : (raw is double ? raw.round() : int.tryParse('$raw'));
    if (v == null || v < 0) throw ApiError(400, '$label مش صحيح');
    if (v > 100000000000) throw ApiError(400, '$label كبير جداً');
    return v;
  }

  String _money(int cents) {
    final pounds = cents / 100;
    return '${pounds == pounds.roundToDouble() ? pounds.toStringAsFixed(0) : pounds.toStringAsFixed(2)} ج.م';
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty && s.length <= 100).take(30).toList();
  }

  String _deviceType(Object? raw) => const {'phone', 'tablet', 'watch', 'laptop', 'other'}.contains(raw) ? raw as String : 'phone';

  String? _validTechnician(Object? raw) {
    if (raw == null || raw == '') return null;
    final row = db.selectOne('SELECT id FROM users WHERE id = ? AND active = 1', [raw]);
    if (row == null) throw ApiError(400, 'الفني ده مش موجود');
    return raw as String;
  }

  String? _validDate(Object? raw) {
    if (raw == null || raw == '') return null;
    final d = DateTime.tryParse('$raw');
    if (d == null) throw ApiError(400, 'التاريخ مش صحيح');
    return d.toUtc().toIso8601String();
  }

  String _randomPin() => List.generate(4, (_) => randomBytes(1)[0] % 10).join();
}

extension on String {
  String? get emptyToNull => isEmpty ? null : this;
}
