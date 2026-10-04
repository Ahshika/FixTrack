part of 'api_server.dart';

/// بيبعت حالة الأجهزة لصفحة التتبع على Firebase، وبيجيب ردود العملاء (حجز معاد، موافقة/رفض).
///
/// كل محل ليه حساب Firebase خاص بيه بيتعمل أوتوماتيك أول مرة (إيميل داخلي وكلمة سر عشوائية
/// متخزنين في إعدادات السيرفر)، وقواعد Firestore بتمنع أي محل يعدّل بيانات محل تاني.
/// لو مفيش نت، الشغل بيكمل عادي والمزامنة بتحصل أول ما النت يرجع.
class FirebaseSync {
  FirebaseSync(this.server);

  final FixTrackServer server;
  final _http = http.Client();
  Timer? _pushTimer;
  Timer? _pullTimer;
  bool _busy = false;

  String? _idToken;
  DateTime _idTokenExpiry = DateTime(2000);
  String? _uid;

  AppDb get db => server.db;
  static const _docsBase = 'https://firestore.googleapis.com/v1/projects/$firebaseProjectId/databases/(default)/documents';

  void start() {
    if (firebaseApiKey.isEmpty) return;
    _pushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _run(push: true));
    _pullTimer = Timer.periodic(const Duration(seconds: 90), (_) => _run(pull: true));
    Timer(const Duration(seconds: 3), () => _run(push: true, pull: true));
  }

  void stop() {
    _pushTimer?.cancel();
    _pullTimer?.cancel();
    _http.close();
  }

  /// بيستنى أي مزامنة شغالة تخلص، وبعدين يعمل مزامنة كاملة.
  Future<void> runNow() async {
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await _run(push: true, pull: true);
  }

  /// بيمسح كل بيانات المحل من Firebase، ومعاها حساب المحل (للاختبارات بس).
  Future<void> deleteEverything() async {
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    _busy = true;
    try {
      final headers = await _headers();
      for (final t in db.select('SELECT public_token FROM tickets')) {
        await _http.delete(Uri.parse('$_docsBase/tracking/${t['public_token']}'), headers: headers);
      }
      await _http.delete(Uri.parse('$_docsBase/shops/$_uid'), headers: headers);
      await _http.post(
        Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:delete?key=$firebaseApiKey'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'idToken': await _token()}),
      );
    } finally {
      _busy = false;
    }
  }

  /// بعد أي تعديل بنحاول نبعت بسرعة بدل ما نستنى الدورة الجاية.
  void kick() => Timer(const Duration(milliseconds: 800), () => _run(push: true));

  Future<void> _run({bool push = false, bool pull = false}) async {
    if (_busy || db.selectOne('SELECT id FROM shop LIMIT 1') == null) return;
    _busy = true;
    try {
      if (push) await _pushDirty();
      if (pull) await _pullActions();
      db.setSetting('cloud_last_sync', nowIso());
      db.setSetting('cloud_last_error', '');
    } catch (e) {
      db.setSetting('cloud_last_error', e is SocketException || e is TimeoutException || e is http.ClientException
          ? 'مفيش نت'
          : '$e');
    } finally {
      _busy = false;
    }
  }

  // ---------------------------------------------------------------- auth

  Future<String> _token() async {
    if (_idToken != null && DateTime.now().isBefore(_idTokenExpiry)) return _idToken!;
    final refresh = db.setting('cloud_refresh_token');
    if (refresh != null && refresh.isNotEmpty) {
      final res = await _http.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$firebaseApiKey'),
        body: {'grant_type': 'refresh_token', 'refresh_token': refresh},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return _saveAuth(j['id_token'] as String, j['refresh_token'] as String, j['user_id'] as String, j['expires_in']);
      }
    }
    var email = db.setting('cloud_email');
    var password = db.setting('cloud_password');
    var endpoint = 'signInWithPassword';
    if (email == null || password == null) {
      email = 'shop-${db.setting('server_id')}@shops.fixtrack.app';
      password = randomToken();
      db.setSetting('cloud_email', email);
      db.setSetting('cloud_password', password);
      endpoint = 'signUp';
    }
    final res = await _http
        .post(
          Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:$endpoint?key=$firebaseApiKey'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password, 'returnSecureToken': true}),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Firebase auth ${res.statusCode}: ${res.body}');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return _saveAuth(j['idToken'] as String, j['refreshToken'] as String, j['localId'] as String, j['expiresIn']);
  }

  String _saveAuth(String idToken, String refreshToken, String uid, Object? expiresIn) {
    db.setSetting('cloud_refresh_token', refreshToken);
    db.setSetting('cloud_uid', uid);
    _uid = uid;
    _idToken = idToken;
    final seconds = int.tryParse('$expiresIn') ?? 3600;
    _idTokenExpiry = DateTime.now().add(Duration(seconds: seconds - 120));
    return idToken;
  }

  Future<Map<String, String>> _headers() async => {
        'authorization': 'Bearer ${await _token()}',
        'content-type': 'application/json',
      };

  // ---------------------------------------------------------------- push

  Future<void> _pushDirty() async {
    final rows = db.select(
      "SELECT t.*, c.name AS customer_name FROM tickets t JOIN customers c ON c.id = t.customer_id "
      "WHERE t.sync_dirty = 1 AND (t.status <> 'delivered' OR t.delivered_at > ?) ORDER BY t.updated_at LIMIT 25",
      [DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String()],
    );
    // الأجهزة اللي اتسلمت من زمان مش محتاجة تتبعت
    db.execute(
      "UPDATE tickets SET sync_dirty = 0 WHERE sync_dirty = 1 AND status = 'delivered' AND delivered_at <= ?",
      [DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String()],
    );
    if (rows.isEmpty) return;

    final headers = await _headers();
    if (db.setting('cloud_shop_synced') != _shopFingerprint()) await _pushShop(headers);

    for (final t in rows) {
      final token = t['public_token'] as String;
      final res = await _http
          .patch(Uri.parse('$_docsBase/tracking/$token'), headers: headers, body: jsonEncode({'fields': _encodeMap(_trackingDoc(t))}))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception('Firestore ${res.statusCode}: ${res.body}');
      // لو الجهاز اتعدل تاني وإحنا بنبعت، هيفضل dirty ويتبعت الدورة الجاية
      db.execute('UPDATE tickets SET sync_dirty = 0 WHERE id = ? AND updated_at = ?', [t['id'], t['updated_at']]);
    }
  }

  String _shopFingerprint() {
    final s = server._shopJson();
    return sha256Hex(jsonEncode([s['name'], s['phone'], s['address'], s['branchName'], s['logoBase64'], s['pickupHours']]));
  }

  Future<void> _pushShop(Map<String, String> headers) async {
    final s = server._shopJson();
    final doc = {
      'ownerUid': _uid,
      'name': s['name'],
      'phone': s['phone'],
      'address': s['address'],
      'branchName': s['branchName'],
      'logo': s['logoBase64'],
      'pickupHours': s['pickupHours'],
      'updatedAt': DateTime.now().toUtc(),
    };
    final res = await _http
        .patch(Uri.parse('$_docsBase/shops/$_uid'), headers: headers, body: jsonEncode({'fields': _encodeMap(doc)}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Firestore shop ${res.statusCode}: ${res.body}');
    db.setSetting('cloud_shop_synced', _shopFingerprint());
  }

  /// البيانات اللي العميل بيشوفها بس: من غير تليفونات، ولا رمز القفل، ولا ملاحظات داخلية.
  Map<String, Object?> _trackingDoc(Map<String, Object?> t) {
    final status = TicketStatus.parse(t['status'] as String?);
    final timeline = db
        .select(
          "SELECT to_value, created_at FROM ticket_events WHERE ticket_id = ? AND type IN ('created', 'status') ORDER BY id",
          [t['id']],
        )
        .map((e) => {'status': e['to_value'], 'at': DateTime.parse(e['created_at'] as String)})
        .toList();
    final paid = db.selectOne('SELECT COALESCE(SUM(amount_cents), 0) AS s FROM payments WHERE ticket_id = ?', [t['id']])!['s'] as int;
    final brand = t['brand'] as String, model = t['model'] as String;
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse(v as String);
    return {
      'ownerUid': _uid,
      'number': t['number'],
      'device': model.toLowerCase().startsWith(brand.toLowerCase()) ? model : '$brand $model',
      'customerName': (t['customer_name'] as String).split(' ').first,
      'status': status.name,
      'statusLabel': status.label,
      'dueAt': date(t['due_at']),
      'totalCents': (t['final_cents'] as int?) ?? (t['estimated_cents'] as int),
      'paidCents': paid,
      'timeline': timeline,
      'approval': t['approval_state'] == null
          ? null
          : {'state': t['approval_state'], 'totalCents': t['approval_cents'], 'note': t['approval_note']},
      'pickupAt': date(t['pickup_at']),
      'deliveredAt': date(t['delivered_at']),
      'createdAt': date(t['created_at']),
      'updatedAt': DateTime.now().toUtc(),
    };
  }

  // ---------------------------------------------------------------- pull

  Future<void> _pullActions() async {
    if (db.setting('cloud_uid') == null) return; // لسه مبعتناش حاجة، يبقى مفيش ردود
    final headers = await _headers();
    final res = await _http
        .post(
          Uri.parse('$_docsBase:runQuery'),
          headers: headers,
          body: jsonEncode({
            'structuredQuery': {
              'from': [
                {'collectionId': 'actions'},
              ],
              'where': {
                'fieldFilter': {
                  'field': {'fieldPath': 'ownerUid'},
                  'op': 'EQUAL',
                  'value': {'stringValue': _uid},
                },
              },
              'limit': 50,
            },
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw Exception('Firestore query ${res.statusCode}: ${res.body}');

    for (final item in jsonDecode(res.body) as List) {
      final doc = (item as Map<String, dynamic>)['document'] as Map<String, dynamic>?;
      if (doc == null) continue;
      final f = _decodeMap(doc['fields'] as Map<String, dynamic>? ?? {});
      try {
        _applyAction(f);
      } catch (e) {
        // رد مش صالح (مثلاً معاد عدّى أو الطلب اتحل قبل كده)، بنتجاهله
      }
      await _http.delete(Uri.parse('https://firestore.googleapis.com/v1/${doc['name']}'), headers: headers).timeout(const Duration(seconds: 20));
    }
  }

  void _applyAction(Map<String, Object?> f) {
    final t = db.selectOne('${_TicketRoutes._ticketSelect} WHERE t.public_token = ?', [f['token']]);
    if (t == null) return;
    switch (f['type']) {
      case 'approve' || 'reject':
        server._applyApproval(t, f['type'] == 'approve', source: 'customer');
      case 'pickup':
        final slot = f['slot'];
        final at = slot is DateTime ? slot : DateTime.tryParse('$slot');
        if (at == null) return;
        server._applyPickup(t, at.toUtc().toIso8601String(), source: 'customer');
    }
  }

  // ---------------------------------------------------------------- generic document access (للفروع)

  Future<String> uid() async {
    await _token();
    return _uid ?? db.setting('cloud_uid')!;
  }

  Future<Map<String, Object?>?> getDoc(String path) async {
    final res = await _http.get(Uri.parse('$_docsBase/$path'), headers: await _headers()).timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw ApiError(502, _cloudError(res));
    return _decodeMap((jsonDecode(res.body) as Map<String, dynamic>)['fields'] as Map<String, dynamic>? ?? {});
  }

  Future<void> setDoc(String path, Map<String, Object?> data) async {
    final res = await _http
        .patch(Uri.parse('$_docsBase/$path'), headers: await _headers(), body: jsonEncode({'fields': _encodeMap(data)}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) throw ApiError(502, _cloudError(res));
  }

  Future<void> deleteDoc(String path) async {
    final res = await _http.delete(Uri.parse('$_docsBase/$path'), headers: await _headers()).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200 && res.statusCode != 404) throw ApiError(502, _cloudError(res));
  }

  Future<List<FsDoc>> listDocs(String collectionPath) async {
    final out = <FsDoc>[];
    String? page;
    do {
      final uri = Uri.parse('$_docsBase/$collectionPath').replace(queryParameters: {'pageSize': '300', 'pageToken': ?page});
      final res = await _http.get(uri, headers: await _headers()).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw ApiError(502, _cloudError(res));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      for (final d in (body['documents'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        out.add(FsDoc((d['name'] as String).split('/').last, _decodeMap(d['fields'] as Map<String, dynamic>? ?? {})));
      }
      page = body['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  String _cloudError(http.Response res) {
    if (res.statusCode == 403) return 'مش مسموح (اتأكد إن الفرع لسه في المجموعة)';
    return 'مشكلة في الاتصال بالنت (${res.statusCode})';
  }

  // ---------------------------------------------------------------- Firestore value encoding

  static Map<String, Object?> _encodeMap(Map<String, Object?> m) => {for (final e in m.entries) e.key: _encode(e.value)};

  static Map<String, Object?> _encode(Object? v) => switch (v) {
        null => {'nullValue': null},
        bool b => {'booleanValue': b},
        int i => {'integerValue': '$i'},
        double d => {'doubleValue': d},
        DateTime d => {'timestampValue': d.toUtc().toIso8601String()},
        String s => {'stringValue': s},
        List l => {
            'arrayValue': {'values': l.map(_encode).toList()},
          },
        Map m => {
            'mapValue': {'fields': _encodeMap(m.cast<String, Object?>())},
          },
        _ => {'stringValue': '$v'},
      };

  static Map<String, Object?> _decodeMap(Map<String, dynamic> fields) => {for (final e in fields.entries) e.key: _decode(e.value as Map<String, dynamic>)};

  static Object? _decode(Map<String, dynamic> v) {
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}');
    if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue')) return v['booleanValue'];
    if (v.containsKey('timestampValue')) return DateTime.tryParse(v['timestampValue'] as String);
    if (v.containsKey('mapValue')) return _decodeMap((v['mapValue'] as Map<String, dynamic>)['fields'] as Map<String, dynamic>? ?? {});
    if (v.containsKey('arrayValue')) {
      return ((v['arrayValue'] as Map<String, dynamic>)['values'] as List? ?? const []).map((e) => _decode(e as Map<String, dynamic>)).toList();
    }
    return null;
  }
}

class FsDoc {
  FsDoc(this.id, this.data);
  final String id;
  final Map<String, Object?> data;
}
