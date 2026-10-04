part of 'api_server.dart';

/// أيام التذكير للأجهزة اللي جاهزة ومحدش استلمها.
const reminderDays = [3, 7, 14, 30];

/// ضمان الصيانة، وقطع الغيار المستخدمة في الأجهزة، وتذكير العملاء اللي ما استلموش.
extension _RepairExtraRoutes on FixTrackServer {
  void _registerRepairExtraRoutes(Router r) {
    r.get('/api/warranty-check', _authed(_warrantyCheck, only: _ticketStaff));
    r.post('/api/tickets/<id>/parts', _authed(_addPart));
    r.delete('/api/tickets/<id>/parts/<partId>', _authed(_removePart));
    r.get('/api/reminders', _authed(_dueReminders, only: _ticketStaff));
  }

  int get _defaultWarrantyDays => int.tryParse(db.setting('repair_warranty_days') ?? '') ?? 30;

  /// أجهزة اتسلمت للعميل ولسه في الضمان (بالتليفون أو الـ IMEI).
  Object? _warrantyCheck(Request req, AuthUser u) {
    final phone = normalizePhone(req.url.queryParameters['phone'] ?? '');
    final imei = latinDigits((req.url.queryParameters['imei'] ?? '').trim());
    if (phone.length < 6 && imei.length < 8) return {'tickets': []};
    final rows = db.select(
      "${_TicketRoutes._ticketSelect} WHERE t.status = 'delivered' AND t.warranty_until > ? AND "
      "(${phone.length >= 6 ? 'c.phone_norm = ?' : '0'} OR ${imei.length >= 8 ? 't.imei = ?' : '0'}) ORDER BY t.delivered_at DESC LIMIT 10",
      [nowIso(), if (phone.length >= 6) phone, if (imei.length >= 8) imei],
    );
    return {'tickets': rows.map(_ticketSummary).toList()};
  }

  /// بتتنادى من استلام جهاز جديد لو اتعلّم كمرتجع ضمان.
  Map<String, Object?> _validWarrantyOrigin(String originId, String customerId, String? imei) {
    final o = db.selectOne('SELECT * FROM tickets WHERE id = ?', [originId]);
    if (o == null) throw ApiError(400, 'الجهاز الأصلي مش موجود');
    if (o['status'] != 'delivered' || o['warranty_until'] == null) throw ApiError(400, 'الجهاز الأصلي مالوش ضمان');
    if ((o['warranty_until'] as String).compareTo(nowIso()) < 0) throw ApiError(400, 'الضمان خلص يوم ${formatDate(DateTime.parse(o['warranty_until'] as String).toLocal())}');
    if (o['customer_id'] != customerId && (imei == null || imei != o['imei'])) throw ApiError(400, 'الجهاز ده مش بتاع نفس العميل');
    return o;
  }

  // ---------------------------------------------------------------- parts

  Future<Object?> _addPart(Request req, AuthUser u) async {
    final t = _loadTicket(req.params['id']!, u);
    final id = t['id'] as String;
    if (t['status'] == 'delivered') throw ApiError(400, 'الجهاز اتسلم خلاص');
    final body = await _body(req);
    final p = db.selectOne('SELECT * FROM products WHERE id = ? AND active = 1', [body['productId']]);
    if (p == null) throw ApiError(400, 'القطعة دي مش موجودة في المخزون');
    if (p['serialized'] == 1) throw ApiError(400, 'الأجهزة بالـ IMEI مابتتركبش كقطع غيار');
    final qty = body['qty'] is int ? body['qty'] as int : 1;
    if (qty <= 0 || qty > 100) throw ApiError(400, 'الكمية مش صحيحة');
    final price = body['priceCents'] == null ? p['price_cents'] as int : _cents(body['priceCents'], 'السعر');
    final addToBill = body['addToBill'] == true && u.role != 'technician';

    db.transaction(() {
      db.execute(
        'INSERT INTO ticket_parts(id, ticket_id, product_id, name, qty, cost_cents, price_cents, user_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [_uuid.v4(), id, p['id'], p['name'], qty, p['cost_cents'], price, u.id, nowIso()],
      );
      _moveStock(p['id'] as String, -qty, 'repair', refType: 'ticket', refId: id, userId: u.id, note: 'جهاز #${t['number']}');
      if (addToBill) {
        final old = (t['final_cents'] as int?) ?? (t['estimated_cents'] as int);
        db.execute('UPDATE tickets SET final_cents = ? WHERE id = ?', [old + price * qty, id]);
        _event(id, 'final_cost', from: '$old', to: '${old + price * qty}', userId: u.id, note: 'إضافة ${p['name']}');
      }
      db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [nowIso(), id]);
      _event(id, 'part', to: '$qty', note: p['name'] as String, userId: u.id);
    });
    _broadcast('tickets');
    _broadcast('products');
    return _ticketDetail(_loadTicket(id, u), u);
  }

  Future<Object?> _removePart(Request req, AuthUser u) async {
    final t = _loadTicket(req.params['id']!, u);
    final id = t['id'] as String;
    if (t['status'] == 'delivered') throw ApiError(400, 'الجهاز اتسلم خلاص');
    final part = db.selectOne('SELECT * FROM ticket_parts WHERE id = ? AND ticket_id = ?', [req.params['partId'], id]);
    if (part == null) throw ApiError(404, 'القطعة دي مش على الجهاز');
    db.transaction(() {
      db.execute('DELETE FROM ticket_parts WHERE id = ?', [part['id']]);
      if (part['product_id'] != null) {
        _moveStock(part['product_id'] as String, part['qty'] as int, 'return', refType: 'ticket', refId: id, userId: u.id, note: 'شيلها من جهاز #${t['number']}');
      }
      db.execute('UPDATE tickets SET updated_at = ? WHERE id = ?', [nowIso(), id]);
      _event(id, 'part_removed', to: '${part['qty']}', note: part['name'] as String, userId: u.id);
    });
    _broadcast('tickets');
    _broadcast('products');
    return _ticketDetail(_loadTicket(id, u), u);
  }

  List<Map<String, Object?>> _ticketParts(String ticketId, {required bool showCost}) => db
      .select('SELECT * FROM ticket_parts WHERE ticket_id = ? ORDER BY created_at', [ticketId])
      .map((p) => {
            'id': p['id'],
            'name': p['name'],
            'qty': p['qty'],
            'priceCents': p['price_cents'],
            if (showCost) 'costCents': p['cost_cents'],
            'createdAt': p['created_at'],
          })
      .toList();

  // ---------------------------------------------------------------- reminders

  /// الأجهزة الجاهزة اللي عدّى عليها أيام التذكير ومحدش استلمها.
  List<Map<String, Object?>> _remindersDue() {
    final rows = db.select(
      "${_TicketRoutes._ticketSelect} WHERE t.status IN ('ready', 'cancelled', 'unrepairable') AND t.ready_at IS NOT NULL",
    );
    final now = DateTime.now().toUtc();
    final due = <Map<String, Object?>>[];
    for (final t in rows) {
      final days = now.difference(DateTime.parse(t['ready_at'] as String)).inDays;
      final sent = t['reminders_sent'] as int;
      final step = reminderDays.lastIndexWhere((d) => days >= d);
      if (step >= 0 && sent <= step) due.add({...t, '_days': days});
    }
    return due;
  }

  Object? _dueReminders(Request req, AuthUser u) => {
        'tickets': _remindersDue().map((t) => {..._ticketSummary(t), 'daysWaiting': t['_days']}).toList(),
      };

  /// بتشتغل كل ساعة: لو التذكير SMS أوتوماتيك بتحط الرسايل في الطابور.
  void _runReminderJob() {
    try {
      final rules = _jsonSetting('message_rules', defaultMessageRules);
      if (MessageRule.parse(rules['reminder'] as String?) != MessageRule.sms) return;
      final hour = DateTime.now().hour;
      if (hour < 10 || hour >= 21) return; // مانبعتش رسايل بالليل
      for (final t in _remindersDue()) {
        _insertMessage(t, 'sms', MessageEvent.reminder, _renderMessage(t, MessageEvent.reminder), null);
        _markReminderSent(t['id'] as String);
      }
    } catch (e) {
      stderr.writeln('reminder job: $e');
    }
  }

  void _markReminderSent(String ticketId) {
    final t = db.selectOne('SELECT ready_at FROM tickets WHERE id = ?', [ticketId]);
    if (t?['ready_at'] == null) return;
    final days = DateTime.now().toUtc().difference(DateTime.parse(t!['ready_at'] as String)).inDays;
    final step = reminderDays.lastIndexWhere((d) => days >= d);
    db.execute('UPDATE tickets SET reminders_sent = ?, last_reminder_at = ? WHERE id = ?', [step + 1, nowIso(), ticketId]);
  }

  /// لما الجهاز يبقى جاهز (أو مرفوض) بنسجل الوقت عشان عداد التذكير.
  void _onStatusChanged(String ticketId, TicketStatus from, TicketStatus to) {
    if (to.awaitingPickup && !from.awaitingPickup) {
      db.execute('UPDATE tickets SET ready_at = ?, reminders_sent = 0 WHERE id = ?', [nowIso(), ticketId]);
    } else if (!to.awaitingPickup) {
      db.execute('UPDATE tickets SET ready_at = NULL WHERE id = ?', [ticketId]);
    }
  }
}
