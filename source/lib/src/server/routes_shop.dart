part of 'api_server.dart';

const receiptPapers = {'80mm', '58mm', 'a5', 'a4'};

extension _ShopRoutes on FixTrackServer {
  void _registerShopRoutes(Router r) {
    r.get('/api/shop', _authed((req, u) => _shopJson()));
    r.patch('/api/shop', _authed(_updateShop, only: {'owner'}));
    r.put('/api/shop/logo', _authed(_setLogo, only: {'owner'}));
    r.delete('/api/shop/logo', _authed((req, u) {
      final f = File(p.join(dataDir, 'logo.png'));
      if (f.existsSync()) f.deleteSync();
      _broadcast('shop');
      return {'ok': true};
    }, only: {'owner'}));

    r.post('/api/cloud/sync', _authed((req, u) async {
      await syncNow();
      return _shopJson();
    }, only: {'owner'}));
    r.get('/api/tickets/<id>/message', _authed(_messagePreview));
    r.post('/api/tickets/<id>/messages', _authed(_logMessage));
    r.get('/api/messages/queue', _authed(_claimSmsQueue));
    r.post('/api/messages/<id>/result', _authed(_smsResult));
  }

  // ---------------------------------------------------------------- shop profile

  Map<String, Object?> _jsonSetting(String key, Map<String, Object?> defaults) {
    final raw = db.setting(key);
    if (raw == null) return {...defaults};
    try {
      return {...defaults, ...(jsonDecode(raw) as Map<String, dynamic>)};
    } catch (_) {
      return {...defaults};
    }
  }

  Map<String, Object?> _shopJson() {
    final shop = db.selectOne('SELECT * FROM shop LIMIT 1');
    final branch = db.selectOne('SELECT * FROM branches WHERE is_local = 1 LIMIT 1');
    final logo = File(p.join(dataDir, 'logo.png'));
    return {
      'name': shop?['name'],
      'phone': shop?['phone'],
      'address': shop?['address'],
      'branchName': branch?['name'],
      'logoBase64': logo.existsSync() ? base64.encode(logo.readAsBytesSync()) : null,
      'receiptTerms': db.setting('receipt_terms') ?? _defaultTerms,
      'receiptPaper': db.setting('receipt_paper') ?? '80mm',
      'trackingBaseUrl': _trackingBase,
      'pickupHours': _jsonSetting('pickup_hours', defaultPickupHours),
      'cashierCanDiscount': db.setting('cashier_can_discount') != '0',
      'repairWarrantyDays': int.tryParse(db.setting('repair_warranty_days') ?? '') ?? 30,
      'allowNegativeStock': db.setting('allow_negative_stock') != '0',
      'cloud': {
        'lastSync': db.setting('cloud_last_sync'),
        'lastError': db.setting('cloud_last_error'),
        'pending': db.selectOne('SELECT COUNT(*) AS c FROM tickets WHERE sync_dirty = 1')!['c'],
      },
      'templates': _jsonSetting('message_templates', defaultTemplates),
      'rules': _jsonSetting('message_rules', defaultMessageRules),
    };
  }

  static const _defaultTerms = 'المحل غير مسؤول عن الأجهزة اللي بتعدّي 30 يوم من غير استلام.\n'
      'المحل غير مسؤول عن البيانات والصور اللي على الجهاز.\n'
      'لازم تقدّم الوصل أو كود الاستلام وقت الاستلام.';

  Future<Object?> _updateShop(Request req, AuthUser u) async {
    final body = await _body(req);
    final shop = db.selectOne('SELECT id FROM shop LIMIT 1');
    if (shop == null) throw ApiError(400, 'المحل لسه ما اتسجلش');

    db.transaction(() {
      if (body.containsKey('name')) {
        db.execute('UPDATE shop SET name = ? WHERE id = ?', [_requiredText(body, 'name', 'اسم المحل'), shop['id']]);
      }
      for (final key in ['phone', 'address']) {
        if (body.containsKey(key)) {
          db.execute('UPDATE shop SET $key = ? WHERE id = ?', [_optionalText(body, key), shop['id']]);
          db.execute('UPDATE branches SET $key = ? WHERE is_local = 1', [_optionalText(body, key)]);
        }
      }
      if (body.containsKey('branchName')) {
        db.execute('UPDATE branches SET name = ? WHERE is_local = 1', [_requiredText(body, 'branchName', 'اسم الفرع')]);
      }
      if (body.containsKey('receiptTerms')) db.setSetting('receipt_terms', (body['receiptTerms'] as String? ?? '').trim());
      if (body.containsKey('receiptPaper')) {
        final paper = body['receiptPaper'];
        if (!receiptPapers.contains(paper)) throw ApiError(400, 'مقاس الورق مش صحيح');
        db.setSetting('receipt_paper', paper as String);
      }
      if (body.containsKey('trackingBaseUrl')) {
        final url = _optionalText(body, 'trackingBaseUrl');
        if (url != null && !url.startsWith('https://')) throw ApiError(400, 'لينك التتبع لازم يبدأ بـ https://');
        db.setSetting('tracking_base_url', url?.replaceAll(RegExp(r'/+$'), '') ?? '');
      }
      if (body['templates'] is Map) {
        final current = _jsonSetting('message_templates', defaultTemplates);
        (body['templates'] as Map).forEach((k, v) {
          if (defaultTemplates.containsKey(k) && v is String) {
            if (v.trim().isEmpty) throw ApiError(400, 'قالب "${MessageEvent.parse(k as String).label}" فاضي');
            if (v.length > 1000) throw ApiError(400, 'القالب طويل جداً');
            current[k as String] = v;
          }
        });
        db.setSetting('message_templates', jsonEncode(current));
      }
      if (body['repairWarrantyDays'] is int) db.setSetting('repair_warranty_days', '${(body['repairWarrantyDays'] as int).clamp(0, 365)}');
      for (final e in const {'cashierCanDiscount': 'cashier_can_discount', 'allowNegativeStock': 'allow_negative_stock'}.entries) {
        if (body[e.key] is bool) db.setSetting(e.value, body[e.key] == true ? '1' : '0');
      }
      if (body['pickupHours'] is Map) {
        final h = body['pickupHours'] as Map;
        final days = (h['days'] as List? ?? const []).whereType<int>().where((d) => d >= 0 && d <= 6).toSet().toList()..sort();
        final timeRe = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
        final from = h['from'] as String? ?? '', to = h['to'] as String? ?? '';
        final slot = h['slotMinutes'] is int ? h['slotMinutes'] as int : 30;
        if (!timeRe.hasMatch(from) || !timeRe.hasMatch(to) || from.compareTo(to) >= 0) throw ApiError(400, 'مواعيد الاستلام مش صحيحة');
        if (![15, 30, 60].contains(slot)) throw ApiError(400, 'مدة الفترة لازم تكون 15 أو 30 أو 60 دقيقة');
        db.setSetting('pickup_hours', jsonEncode({'days': days, 'from': from, 'to': to, 'slotMinutes': slot}));
      }
      if (body['rules'] is Map) {
        final current = _jsonSetting('message_rules', defaultMessageRules);
        (body['rules'] as Map).forEach((k, v) {
          if (defaultMessageRules.containsKey(k)) current[k as String] = MessageRule.parse(v as String?).name;
        });
        db.setSetting('message_rules', jsonEncode(current));
      }
    });
    // بيانات المحل بتظهر في صفحة التتبع، فكل الأجهزة اللي لسه في المحل محتاجة تتحدّث
    db.execute("UPDATE tickets SET sync_dirty = 1 WHERE status <> 'delivered'");
    _audit(u.id, 'shop.update', 'shop', shop['id'] as String, body.keys.join('، '));
    _broadcast('shop');
    return _shopJson();
  }

  Future<Object?> _setLogo(Request req, AuthUser u) async {
    final body = await _body(req);
    final List<int> bytes;
    try {
      bytes = base64.decode(body['png'] as String? ?? '');
    } catch (_) {
      throw ApiError(400, 'الصورة مش صحيحة');
    }
    const pngMagic = [0x89, 0x50, 0x4E, 0x47];
    if (bytes.length < 8 || !List.generate(4, (i) => bytes[i] == pngMagic[i]).every((b) => b)) {
      throw ApiError(400, 'الصورة لازم تكون PNG');
    }
    if (bytes.length > 1024 * 1024) throw ApiError(400, 'الصورة كبيرة جداً');
    File(p.join(dataDir, 'logo.png')).writeAsBytesSync(bytes);
    _audit(u.id, 'shop.logo', 'shop', null, null);
    _broadcast('shop');
    return {'ok': true};
  }

  // ---------------------------------------------------------------- messages

  /// لينك صفحة التتبع: الافتراضي موقع FixTrack، والمحل يقدر يغيّره (أو يقفله بقيمة فاضية).
  String? get _trackingBase {
    final custom = db.setting('tracking_base_url');
    if (custom == null) return trackingSiteUrl;
    return custom.isEmpty ? null : custom;
  }

  String? _trackingLink(Map<String, Object?> ticket) {
    final base = _trackingBase;
    return base == null ? null : '$base/t/${ticket['public_token']}';
  }

  /// بيملا قالب الحدث ببيانات الجهاز.
  String _renderMessage(Map<String, Object?> t, MessageEvent event, {String? template}) {
    final shop = _shopJson();
    final templates = shop['templates'] as Map<String, Object?>;
    final total = (t['final_cents'] as int?) ?? (t['estimated_cents'] as int);
    final paid = t['paid_cents'] as int? ?? 0;
    final due = t['due_at'] == null ? null : DateTime.tryParse(t['due_at'] as String)?.toLocal();
    final brand = t['brand'] as String, model = t['model'] as String;
    return renderTemplate(template ?? (templates[event.name] as String? ?? defaultTemplates[event.name]!), {
      'customer': t['customer_name'] as String?,
      'device': model.toLowerCase().startsWith(brand.toLowerCase()) ? model : '$brand $model',
      'number': '${t['number']}',
      'pin': t['pickup_pin'] as String?,
      'status': TicketStatus.parse(t['status'] as String?).label,
      'due': due == null ? null : formatDateTime(due),
      'total': total > 0 ? money(total) : null,
      'paid': paid > 0 ? money(paid) : null,
      'remaining': total - paid > 0 ? money(total - paid) : 'مفيش، الحساب خالص',
      'link': _trackingLink(t),
      'shop': shop['name'] as String?,
      'shop_phone': shop['phone'] as String?,
      'days': t['ready_at'] == null ? null : '${DateTime.now().toUtc().difference(DateTime.parse(t['ready_at'] as String)).inDays}',
    });
  }

  String _customerPhone(Map<String, Object?> t, {bool whatsapp = false}) {
    final wa = t['customer_whatsapp'] as String?;
    return whatsapp && wa != null && wa.trim().isNotEmpty ? wa : t['customer_phone'] as String;
  }

  Object? _messagePreview(Request req, AuthUser u) {
    final t = _loadTicket(req.params['id']!, u);
    final event = MessageEvent.parse(req.url.queryParameters['event']);
    return {
      'event': event.name,
      'body': _renderMessage(t, event),
      'phone': _customerPhone(t),
      'whatsapp': whatsappNumber(_customerPhone(t, whatsapp: true)),
    };
  }

  Future<Object?> _logMessage(Request req, AuthUser u) async {
    final t = _loadTicket(req.params['id']!, u);
    final body = await _body(req);
    final channel = body['channel'] == 'sms' ? 'sms' : 'whatsapp';
    final text = _requiredText(body, 'body', 'نص الرسالة');
    final event = MessageEvent.parse(body['event'] as String?);
    final id = _insertMessage(t, channel, event, text, u.id);
    if (event == MessageEvent.reminder) _markReminderSent(t['id'] as String);
    return {'id': id};
  }

  String _insertMessage(Map<String, Object?> t, String channel, MessageEvent event, String text, String? userId) {
    final id = _uuid.v4();
    db.execute(
      'INSERT INTO messages(id, ticket_id, customer_id, phone, channel, event, body, status, user_id, created_at) '
      'VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id, t['id'], t['customer_id'], _customerPhone(t, whatsapp: channel == 'whatsapp'),
        channel, event.name, text, channel == 'sms' ? 'queued' : 'opened', userId, nowIso(),
      ],
    );
    _broadcast('messages');
    _broadcast('tickets');
    return id;
  }

  /// لو قاعدة الحدث ده "SMS أوتوماتيك"، بتتحط رسالة في الطابور وأي موبايل شغال كبوابة SMS بيبعتها.
  void _autoMessage(String ticketId, MessageEvent event) {
    final rules = _jsonSetting('message_rules', defaultMessageRules);
    if (MessageRule.parse(rules[event.name] as String?) != MessageRule.sms) return;
    final t = db.selectOne('${_TicketRoutes._ticketSelect} WHERE t.id = ?', [ticketId]);
    if (t == null) return;
    _insertMessage(t, 'sms', event, _renderMessage(t, event), null);
  }

  Object? _claimSmsQueue(Request req, AuthUser u) {
    final device = req.url.queryParameters['device'] ?? u.id;
    final stale = DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String();
    final rows = db.transaction(() {
      final rows = db.select(
        "SELECT id, phone, body FROM messages WHERE channel = 'sms' AND "
        "(status = 'queued' OR (status = 'sending' AND claimed_at < ?)) ORDER BY created_at LIMIT 5",
        [stale],
      );
      for (final m in rows) {
        db.execute("UPDATE messages SET status = 'sending', claimed_by = ?, claimed_at = ? WHERE id = ?", [device, nowIso(), m['id']]);
      }
      return rows;
    });
    return {'messages': rows};
  }

  Future<Object?> _smsResult(Request req, AuthUser u) async {
    final body = await _body(req);
    final ok = body['ok'] == true;
    db.execute(
      'UPDATE messages SET status = ?, error = ?, sent_at = ? WHERE id = ?',
      [ok ? 'sent' : 'failed', ok ? null : (body['error'] as String? ?? 'فشل الإرسال'), ok ? nowIso() : null, req.params['id']],
    );
    _broadcast('messages');
    _broadcast('tickets');
    return {'ok': true};
  }

  List<Map<String, Object?>> _ticketMessages(String ticketId) => db
      .select(
        'SELECT m.*, u.name AS user_name FROM messages m LEFT JOIN users u ON u.id = m.user_id '
        'WHERE m.ticket_id = ? ORDER BY m.created_at DESC',
        [ticketId],
      )
      .map((m) => {
            'id': m['id'],
            'channel': m['channel'],
            'event': m['event'],
            'body': m['body'],
            'status': m['status'],
            'error': m['error'],
            'phone': m['phone'],
            'userName': m['user_name'],
            'createdAt': m['created_at'],
            'sentAt': m['sent_at'],
          })
      .toList();
}
