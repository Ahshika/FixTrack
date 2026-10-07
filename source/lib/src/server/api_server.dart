import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_info.dart';
import '../core/diagnostics.dart';
import '../core/firebase_config.dart';
import '../core/format.dart';
import '../core/license.dart';
import '../core/messages.dart';
import '../core/ticket_status.dart';
import 'db.dart';
import 'discovery.dart';
import 'passwords.dart';
import 'secret_box.dart';

part 'firebase_sync.dart';
part 'routes_approval.dart';
part 'routes_pos.dart';
part 'routes_repair_extra.dart';
part 'routes_reports.dart';
part 'routes_org.dart';
part 'routes_license.dart';
part 'backup_service.dart';
part 'routes_services.dart';
part 'routes_stock.dart';
part 'routes_shop.dart';
part 'routes_tickets.dart';

const serverPort = 8743;
const roles = {'owner', 'reception', 'technician'};
const _uuid = Uuid();

String nowIso() => DateTime.now().toUtc().toIso8601String();

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => 'ApiError($status): $message';
}

class AuthUser {
  AuthUser(this.row, this.tokenHash);
  final Map<String, Object?> row;
  final String tokenHash;
  String get id => row['id'] as String;
  String get role => row['role'] as String;
  bool get isOwner => role == 'owner';
}

/// سيرفر المحل: بيشتغل على كمبيوتر المحل، وكل الموبايلات والكمبيوترات التانية بتكلمه.
class FixTrackServer {
  FixTrackServer({required this.dataDir, this.requestedPort = serverPort, this.cloudSync = true});

  final String dataDir;
  final int requestedPort;

  /// المزامنة مع صفحة التتبع على Firebase (بتتقفل في الاختبارات).
  final bool cloudSync;
  FirebaseSync? _cloud;
  Timer? _jobsTimer;
  Timer? _firstJobTimer;

  /// البورت الفعلي (بيفرق عن requestedPort لو طلبنا 0 في الاختبارات).
  int get port => _http?.port ?? requestedPort;

  late final AppDb db;
  late final DiagLog _log = DiagLog.openIn(dataDir, 'server');
  HttpServer? _http;
  DiscoveryResponder? _discovery;
  final _sockets = <WebSocketChannel>{};
  final _loginFailures = <String, _Failures>{};
  final _lastSeenWrites = <String, DateTime>{};

  Future<void> start() async {
    await initializeDateFormatting('ar');
    await Directory(dataDir).create(recursive: true);
    applyPendingRestore(dataDir);
    db = AppDb.open(p.join(dataDir, 'fixtrack.db'));
    if (db.setting('server_id') == null) db.setSetting('server_id', _uuid.v4());
    _log.write('INFO', 'السيرفر اشتغل ($appName $appVersion)');
    final health = db.integrity();
    if (health != 'ok') _log.write('ERROR', 'فحص قاعدة البيانات لقى مشكلة: $health (ارجع لآخر نسخة احتياطية من الإعدادات)');
    db.setSetting('db_health', health);

    final handler = const Pipeline().addMiddleware(_errors()).addHandler(_router().call);
    try {
      // طابور اتصالات أكبر: لما أجهزة كتير تتصل في نفس اللحظة ماتترفضش
      _http = await shelf_io.serve(handler, InternetAddress.anyIPv4, requestedPort, shared: false, backlog: 1024);
    } on SocketException {
      db.close();
      throw ApiError(500, 'البورت $requestedPort مستخدم. غالباً البرنامج مفتوح بالفعل على الجهاز ده.');
    }
    _http!.autoCompress = true;

    _discovery = DiscoveryResponder(() {
      final info = _info();
      return {'port': port, 'shopName': info['shopName'], 'branchName': info['branchName'], 'serverId': info['serverId']};
    });
    try {
      await _discovery!.start();
    } catch (_) {
      // لو بورت البحث مش متاح، الموبايلات لسه تقدر تتصل يدوي بالـ IP
    }

    if (cloudSync) _cloud = FirebaseSync(this)..start();

    // شغل بيتكرر: تذكير العملاء اللي ما استلموش، والنسخ الاحتياطي اليومي
    Future<void> jobs() async {
      db.maintenance();
      _runReminderJob();
      await _runBackupIfDue();
      await _pushOrgData();
    }

    Future<void> safeJobs() => jobs().catchError((Object e, StackTrace st) => _log.error('الشغل الدوري: $e', st));
    _jobsTimer = Timer.periodic(const Duration(hours: 1), (_) => safeJobs());
    _firstJobTimer = Timer(const Duration(minutes: 1), safeJobs);
  }

  /// مزامنة فورية مع صفحة التتبع (للاختبارات وزرار "مزامنة دلوقتي").
  Future<void> syncNow() async => _cloud?.runNow();

  /// بيمسح بيانات مجموعة الفروع من Firebase (للاختبارات بس، ولازم يتنادى من الفرع اللي عمل المجموعة).
  Future<void> cleanupOrgForTests(String? transferId) async {
    Future<void> safe(Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        stderr.writeln("org cleanup: $e");
      }
    }

    final orgId = db.setting('org_id');
    final fb = _cloud;
    if (orgId == null || orgId.isEmpty || fb == null) return;
    final uid = await fb.uid();
    for (final d in await fb.listDocs('orgs/$orgId/branches/$uid/days')) {
      await safe(() => fb.deleteDoc('orgs/$orgId/branches/$uid/days/${d.id}'));
    }
    await safe(() => fb.deleteDoc('orgs/$orgId/branches/$uid'));
    if (transferId != null) await safe(() => fb.deleteDoc('orgs/$orgId/transfers/$transferId'));
    await safe(() => fb.deleteDoc('orgs/$orgId/members/$uid'));
    await safe(() => fb.deleteDoc('orgs/$orgId'));
    db.setSetting('org_id', '');
  }

  /// بيمسح كل بيانات المحل من Firebase (للاختبارات بس).
  Future<void> cleanupCloudForTests() async => _cloud?.deleteEverything();

  /// آخر خطأ في المزامنة (فاضي لو كله تمام).
  String? get cloudError => db.setting('cloud_last_error');

  Future<void> stop() async {
    _cloud?.stop();
    _jobsTimer?.cancel();
    _firstJobTimer?.cancel();
    _discovery?.close();
    for (final s in _sockets) {
      await s.sink.close();
    }
    await _http?.close(force: true);
    db.close();
  }

  // ---------------------------------------------------------------- routing

  Router _router() {
    final r = Router();
    r.get('/api/info', _public((_) => _info()));
    r.post('/api/setup', _public(_setup));
    r.post('/api/auth/login', _public(_login));
    r.post('/api/auth/logout', _authed((req, u) {
      db.execute('DELETE FROM sessions WHERE token_hash = ?', [u.tokenHash]);
      return {'ok': true};
    }));
    r.get('/api/auth/me', _authed((req, u) => {'user': _publicUser(u.row)}));
    r.post('/api/auth/password', _authed(_changeOwnPassword));

    r.get('/api/users', _authed(_listUsers, only: {'owner'}));
    r.post('/api/users', _authed(_createUser, only: {'owner'}));
    r.patch('/api/users/<id>', _authed(_updateUser, only: {'owner'}));

    r.get('/api/audit', _authed(_listAudit, only: {'owner'}));
    _registerTicketRoutes(r);
    _registerShopRoutes(r);
    _registerApprovalRoutes(r);
    _registerPosRoutes(r);
    _registerStockRoutes(r);
    _registerServiceRoutes(r);
    _registerRepairExtraRoutes(r);
    _registerBackupRoutes(r);
    _registerReportRoutes(r);
    _registerOrgRoutes(r);
    _registerLicenseRoutes(r);

    r.get('/api/ws', _webSocket);
    r.all('/<ignored|.*>', (Request _) => _json(404, {'error': 'المسار ده مش موجود'}));
    return r;
  }

  Middleware _errors() => (inner) => (req) async {
        final sw = Stopwatch()..start();
        try {
          final res = await inner(req);
          if (sw.elapsedMilliseconds > 700 && !req.url.path.startsWith('api/ws')) {
            _log.write('SLOW', '${req.method} /${req.url.path} خد ${sw.elapsedMilliseconds} مللي ثانية');
          }
          return res;
        } on ApiError catch (e) {
          return _json(e.status, {'error': e.message});
        } on HijackException {
          // ده مش خطأ: الـ WebSocket بياخد الاتصال، وshelf لازم يشوف الاستثناء ده عشان يكمّل
          rethrow;
        } catch (e, st) {
          stderr.writeln('Server error on ${req.method} ${req.url}: $e\n$st');
          _log.error('${req.method} /${req.url.path}: $e', st);
          return _json(500, {'error': 'حصل خطأ في السيرفر، جرّب تاني'});
        }
      };

  Handler _public(FutureOr<Object?> Function(Request req) fn) => (req) async => _json(200, await fn(req));

  Handler _authed(FutureOr<Object?> Function(Request req, AuthUser user) fn, {Set<String>? only}) => (req) async {
        final user = _authenticate(req);
        if (only != null && !only.contains(user.role)) {
          throw ApiError(403, 'مش مسموحلك تعمل العملية دي');
        }
        final result = await fn(req, user);
        // الملفات (زي صور البطايق) بترجع Response جاهز مش JSON
        return result is Response ? result : _json(200, result);
      };

  AuthUser _authenticate(Request req) {
    final header = req.headers['authorization'];
    final token = header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : req.url.queryParameters['token'];
    if (token == null || token.isEmpty) throw ApiError(401, 'لازم تسجل دخول الأول');

    final tokenHash = sha256Hex(token);
    final row = db.selectOne(
      'SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?',
      [tokenHash],
    );
    if (row == null) throw ApiError(401, 'الجلسة انتهت، سجل دخول تاني');
    if (row['active'] != 1) throw ApiError(401, 'الحساب ده متوقف، كلم صاحب المحل');
    // آخر ظهور للجهاز بيتسجل مرة كل دقيقة بس، مش مع كل طلب (كانت كتابة زيادة في كل عملية)
    final now = DateTime.now();
    final last = _lastSeenWrites[tokenHash];
    if (last == null || now.difference(last) > const Duration(minutes: 1)) {
      _lastSeenWrites[tokenHash] = now;
      db.execute('UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?', [nowIso(), tokenHash]);
    }
    return AuthUser(row, tokenHash);
  }

  // ---------------------------------------------------------------- setup & auth

  Map<String, Object?> _info() {
    final shop = db.selectOne('SELECT name FROM shop LIMIT 1');
    final branch = db.selectOne('SELECT name FROM branches WHERE is_local = 1 LIMIT 1');
    return {
      'app': 'fixtrack',
      'api': apiVersion,
      'version': appVersion,
      'serverId': db.setting('server_id'),
      'setupDone': shop != null,
      'shopName': shop?['name'],
      'branchName': branch?['name'],
    };
  }

  Future<Object?> _setup(Request req) async {
    final body = await _body(req);
    if (db.selectOne('SELECT id FROM shop LIMIT 1') != null) {
      throw ApiError(409, 'المحل متسجل بالفعل على السيرفر ده');
    }
    final shopName = _requiredText(body, 'shopName', 'اسم المحل');
    final branchName = _optionalText(body, 'branchName') ?? 'الفرع الرئيسي';
    final ownerName = _requiredText(body, 'ownerName', 'اسم صاحب المحل');
    final username = _validUsername(body['username']);
    final password = _validPassword(body['password']);
    final now = nowIso();
    final shopId = _uuid.v4(), branchId = _uuid.v4(), userId = _uuid.v4();
    final passwordHash = hashPassword(password);

    db.transaction(() {
      db.execute('INSERT INTO shop(id, name, phone, address, created_at) VALUES(?, ?, ?, ?, ?)',
          [shopId, shopName, _optionalText(body, 'shopPhone'), _optionalText(body, 'shopAddress'), now]);
      db.execute('INSERT INTO branches(id, name, phone, address, is_local, created_at) VALUES(?, ?, ?, ?, 1, ?)',
          [branchId, branchName, _optionalText(body, 'shopPhone'), _optionalText(body, 'shopAddress'), now]);
      db.execute(
        'INSERT INTO users(id, branch_id, name, username, password_hash, role, active, created_at, updated_at) '
        'VALUES(?, ?, ?, ?, ?, \'owner\', 1, ?, ?)',
        [userId, branchId, ownerName, username, passwordHash, now, now],
      );
    });
    _audit(userId, 'shop.setup', 'shop', shopId, shopName);
    db.setSetting('trial_started', nowIso());
    final user = db.selectOne('SELECT * FROM users WHERE id = ?', [userId])!;
    return {'token': _createSession(userId, body['deviceName']), 'user': _publicUser(user)};
  }

  Future<Object?> _login(Request req) async {
    final ip = _clientIp(req);
    final failures = _loginFailures[ip];
    if (failures != null && failures.lockedUntil != null && DateTime.now().isBefore(failures.lockedUntil!)) {
      final seconds = failures.lockedUntil!.difference(DateTime.now()).inSeconds + 1;
      throw ApiError(429, 'محاولات كتير غلط. استنى $seconds ثانية وجرّب تاني');
    }

    final body = await _body(req);
    final username = (body['username'] as String? ?? '').trim().toLowerCase();
    final password = body['password'] as String? ?? '';
    final user = db.selectOne('SELECT * FROM users WHERE username = ?', [username]);

    if (user == null || !verifyPassword(password, user['password_hash'] as String)) {
      final f = _loginFailures.putIfAbsent(ip, _Failures.new);
      f.count++;
      if (f.count >= 5) {
        f.lockedUntil = DateTime.now().add(const Duration(minutes: 1));
        f.count = 0;
      }
      throw ApiError(401, 'اسم المستخدم أو كلمة السر غلط');
    }
    if (user['active'] != 1) throw ApiError(403, 'الحساب ده متوقف، كلم صاحب المحل');

    await _checkDeviceLimit(body['deviceName'] as String?);
    _loginFailures.remove(ip);
    _audit(user['id'] as String, 'auth.login', 'user', user['id'] as String, body['deviceName'] as String?);
    return {'token': _createSession(user['id'] as String, body['deviceName']), 'user': _publicUser(user)};
  }

  Future<Object?> _changeOwnPassword(Request req, AuthUser u) async {
    final body = await _body(req);
    if (!verifyPassword(body['currentPassword'] as String? ?? '', u.row['password_hash'] as String)) {
      throw ApiError(400, 'كلمة السر الحالية غلط');
    }
    final password = _validPassword(body['newPassword']);
    db.transaction(() {
      db.execute('UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?', [hashPassword(password), nowIso(), u.id]);
      // نخرج من كل الأجهزة التانية ونسيب الجهاز الحالي بس
      db.execute('DELETE FROM sessions WHERE user_id = ? AND token_hash <> ?', [u.id, u.tokenHash]);
    });
    _audit(u.id, 'user.password', 'user', u.id, null);
    return {'ok': true};
  }

  String _createSession(String userId, Object? deviceName) {
    final token = randomToken();
    final now = nowIso();
    db.execute(
      'INSERT INTO sessions(token_hash, user_id, device_name, created_at, last_seen_at) VALUES(?, ?, ?, ?, ?)',
      [sha256Hex(token), userId, deviceName is String ? deviceName : null, now, now],
    );
    return token;
  }

  // ---------------------------------------------------------------- users

  Object? _listUsers(Request req, AuthUser u) {
    final rows = db.select('SELECT * FROM users ORDER BY active DESC, role, name');
    return {'users': rows.map(_publicUser).toList()};
  }

  Future<Object?> _createUser(Request req, AuthUser u) async {
    final body = await _body(req);
    final name = _requiredText(body, 'name', 'الاسم');
    final username = _validUsername(body['username']);
    final password = _validPassword(body['password']);
    final role = _validRole(body['role']);
    if (db.selectOne('SELECT id FROM users WHERE username = ?', [username]) != null) {
      throw ApiError(409, 'اسم المستخدم "$username" موجود بالفعل، اختار اسم تاني');
    }
    final id = _uuid.v4();
    final now = nowIso();
    final branchId = db.selectOne('SELECT id FROM branches WHERE is_local = 1 LIMIT 1')?['id'];
    db.execute(
      'INSERT INTO users(id, branch_id, name, username, password_hash, role, active, created_at, updated_at) '
      'VALUES(?, ?, ?, ?, ?, ?, 1, ?, ?)',
      [id, branchId, name, username, hashPassword(password), role, now, now],
    );
    _audit(u.id, 'user.create', 'user', id, '$name ($role)');
    _broadcast('users');
    return {'user': _publicUser(db.selectOne('SELECT * FROM users WHERE id = ?', [id])!)};
  }

  Future<Object?> _updateUser(Request req, AuthUser u) async {
    final id = req.params['id']!;
    final target = db.selectOne('SELECT * FROM users WHERE id = ?', [id]);
    if (target == null) throw ApiError(404, 'الموظف ده مش موجود');
    final body = await _body(req);

    final name = body.containsKey('name') ? _requiredText(body, 'name', 'الاسم') : target['name'] as String;
    final role = body.containsKey('role') ? _validRole(body['role']) : target['role'] as String;
    final active = body.containsKey('active') ? (body['active'] == true ? 1 : 0) : target['active'] as int;
    final newPassword = body['password'] is String && (body['password'] as String).isNotEmpty
        ? _validPassword(body['password'])
        : null;

    if (id == u.id && (role != 'owner' || active != 1)) {
      throw ApiError(400, 'مينفعش توقف حسابك أو تغيّر صلاحيتك بنفسك');
    }
    if (target['role'] == 'owner' && (role != 'owner' || active != 1)) {
      final owners = db.selectOne("SELECT COUNT(*) AS c FROM users WHERE role = 'owner' AND active = 1")!['c'] as int;
      if (owners <= 1) throw ApiError(400, 'لازم يفضل فيه مالك واحد على الأقل');
    }

    db.transaction(() {
      db.execute('UPDATE users SET name = ?, role = ?, active = ?, updated_at = ? WHERE id = ?', [name, role, active, nowIso(), id]);
      if (const {'none', 'percent', 'fixed'}.contains(body['commissionType'])) {
        final value = body['commissionValue'] is int ? (body['commissionValue'] as int).clamp(0, body['commissionType'] == 'percent' ? 10000 : 100000000) : 0;
        db.execute('UPDATE users SET commission_type = ?, commission_value = ? WHERE id = ?', [body['commissionType'], value, id]);
      }
      if (newPassword != null) {
        db.execute('UPDATE users SET password_hash = ? WHERE id = ?', [hashPassword(newPassword), id]);
      }
      // أي تغيير في الصلاحية أو الإيقاف أو كلمة السر بيخرج الموظف من كل أجهزته
      if (newPassword != null || active != 1 || role != target['role']) {
        db.execute('DELETE FROM sessions WHERE user_id = ?', [id]);
      }
    });
    final changes = [
      if (name != target['name']) 'الاسم: من ${target['name']} لـ $name',
      if (role != target['role']) 'الصلاحية: من ${target['role']} لـ $role',
      if (active != target['active']) active == 1 ? 'تفعيل الحساب' : 'إيقاف الحساب',
      if (newPassword != null) 'تغيير كلمة السر',
    ];
    if (changes.isNotEmpty) _audit(u.id, 'user.update', 'user', id, changes.join('، '));
    _broadcast('users');
    return {'user': _publicUser(db.selectOne('SELECT * FROM users WHERE id = ?', [id])!)};
  }

  Map<String, Object?> _publicUser(Map<String, Object?> row) => {
        'id': row['id'],
        'name': row['name'],
        'username': row['username'],
        'role': row['role'],
        'active': row['active'] == 1,
        'branchId': row['branch_id'],
        'commissionType': row['commission_type'] ?? 'none',
        'commissionValue': row['commission_value'] ?? 0,
        'createdAt': row['created_at'],
      };

  // ---------------------------------------------------------------- audit

  void _audit(String? userId, String action, String? entity, String? entityId, String? details) {
    db.execute(
      'INSERT INTO audit_log(user_id, action, entity, entity_id, details, created_at) VALUES(?, ?, ?, ?, ?, ?)',
      [userId, action, entity, entityId, details, nowIso()],
    );
  }

  Object? _listAudit(Request req, AuthUser u) {
    final limit = (int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 100).clamp(1, 500);
    final before = int.tryParse(req.url.queryParameters['before'] ?? '');
    final rows = db.select(
      'SELECT a.*, u.name AS user_name FROM audit_log a LEFT JOIN users u ON u.id = a.user_id '
      '${before != null ? 'WHERE a.id < ?' : ''} ORDER BY a.id DESC LIMIT ?',
      [?before, limit],
    );
    return {
      'entries': rows
          .map((r) => {
                'id': r['id'],
                'userName': r['user_name'],
                'action': r['action'],
                'details': r['details'],
                'createdAt': r['created_at'],
              })
          .toList(),
    };
  }

  // ---------------------------------------------------------------- realtime

  FutureOr<Response> _webSocket(Request req) {
    _authenticate(req);
    return webSocketHandler((WebSocketChannel ch, String? _) {
      _sockets.add(ch);
      ch.stream.listen((_) {}, onDone: () => _sockets.remove(ch), onError: (_) => _sockets.remove(ch));
    })(req);
  }

  /// بيبلّغ كل الأجهزة المتصلة إن فيه حاجة اتغيرت عشان تحدّث الشاشة.
  void _broadcast(String topic) {
    if (topic == 'tickets' || topic == 'shop') _cloud?.kick();
    final msg = jsonEncode({'type': 'changed', 'topic': topic});
    for (final s in _sockets.toList()) {
      try {
        s.sink.add(msg);
      } catch (_) {
        _sockets.remove(s);
      }
    }
  }

  // ---------------------------------------------------------------- helpers

  Response _json(int status, Object? body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<Map<String, dynamic>> _body(Request req) async {
    final text = await req.readAsString();
    if (text.isEmpty) return {};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw ApiError(400, 'البيانات المبعوتة مش مفهومة');
  }

  String _clientIp(Request req) =>
      (req.context['shelf.io.connection_info'] as HttpConnectionInfo?)?.remoteAddress.address ?? 'unknown';

  String _requiredText(Map<String, dynamic> body, String key, String label) {
    final v = (body[key] as String? ?? '').trim();
    if (v.isEmpty) throw ApiError(400, 'لازم تكتب $label');
    if (v.length > 200) throw ApiError(400, '$label طويل جداً');
    return v;
  }

  String? _optionalText(Map<String, dynamic> body, String key) {
    final v = (body[key] as String? ?? '').trim();
    return v.isEmpty ? null : v;
  }

  String _validUsername(Object? raw) {
    final v = (raw as String? ?? '').trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_.]{3,30}$').hasMatch(v)) {
      throw ApiError(400, 'اسم المستخدم لازم يكون بالإنجليزي من 3 لـ 30 حرف (حروف وأرقام و _ و . بس)');
    }
    return v;
  }

  String _validPassword(Object? raw) {
    final v = raw as String? ?? '';
    if (v.length < 6) throw ApiError(400, 'كلمة السر لازم تكون 6 حروف أو أرقام على الأقل');
    if (v.length > 100) throw ApiError(400, 'كلمة السر طويلة جداً');
    return v;
  }

  String _validRole(Object? raw) {
    if (raw is! String || !roles.contains(raw)) throw ApiError(400, 'الصلاحية مش صحيحة');
    return raw;
  }
}

class _Failures {
  int count = 0;
  DateTime? lockedUntil;
}
