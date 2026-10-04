import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../server/server_host.dart';
import 'api_client.dart';
import 'app_config.dart';
import 'models.dart';

final appConfigProvider = Provider<AppConfig>((ref) => throw UnimplementedError('overridden in main'));

enum SessionStatus {
  /// أول تشغيل: الجهاز ده هيبقى سيرفر ولا هيتصل بسيرفر؟
  chooseMode,

  /// السيرفر ما اشتغلش على الجهاز ده
  serverFailed,

  /// مش قادرين نوصل للسيرفر (للأجهزة المتصلة)
  unreachable,

  /// الجهاز محتاج يختار سيرفر يتصل بيه
  needsServer,

  /// السيرفر شغال بس المحل لسه ما اتسجلش
  needsSetup,
  needsLogin,
  ready,
}

class Session {
  const Session(this.status, {this.api, this.info, this.user, this.error});

  final SessionStatus status;
  final ApiClient? api;
  final ServerInfo? info;
  final AppUser? user;
  final String? error;
}

final sessionProvider = AsyncNotifierProvider<SessionController, Session>(SessionController.new);

/// قلب البرنامج: بيقرر المستخدم يشوف أنهي شاشة، وبيمسك الاتصال بالسيرفر.
class SessionController extends AsyncNotifier<Session> {
  AppConfig get _config => ref.read(appConfigProvider);

  @override
  Future<Session> build() async {
    final mode = _config.mode;
    if (mode == null) return const Session(SessionStatus.chooseMode);

    final String baseUrl;
    if (mode == AppMode.server) {
      try {
        final dir = await getApplicationSupportDirectory();
        final port = await ServerHost.start(dir.path);
        baseUrl = 'http://127.0.0.1:$port';
      } catch (e) {
        return Session(SessionStatus.serverFailed, error: e.toString());
      }
    } else {
      final url = _config.serverUrl;
      if (url == null) return const Session(SessionStatus.needsServer);
      baseUrl = url;
    }

    final api = ApiClient(baseUrl, token: _config.token, onUnauthorized: _onUnauthorized);
    ref.onDispose(api.close);

    final ServerInfo info;
    try {
      info = ServerInfo.fromJson(await api.get('/api/info'));
    } on ApiException catch (e) {
      return Session(SessionStatus.unreachable, api: api, error: e.message);
    } on FormatException {
      return Session(SessionStatus.unreachable, api: api, error: 'العنوان ده مش سيرفر FixTrack');
    }

    if (!info.setupDone) return Session(SessionStatus.needsSetup, api: api, info: info);
    if (_config.token == null) return Session(SessionStatus.needsLogin, api: api, info: info);

    try {
      final me = await api.get('/api/auth/me');
      return Session(SessionStatus.ready, api: api, info: info, user: AppUser.fromJson(me['user'] as Map<String, dynamic>));
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _config.setToken(null);
        api.token = null;
        return Session(SessionStatus.needsLogin, api: api, info: info, error: e.message);
      }
      return Session(SessionStatus.unreachable, api: api, info: info, error: e.message);
    }
  }

  Session? get _current => state.value;

  void _onUnauthorized() {
    final s = _current;
    if (s == null || s.status != SessionStatus.ready) return;
    _config.setToken(null);
    s.api?.token = null;
    state = AsyncData(Session(SessionStatus.needsLogin, api: s.api, info: s.info, error: 'الجلسة انتهت، سجل دخول تاني'));
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    ref.invalidateSelf();
    await future;
  }

  Future<void> chooseMode(AppMode mode) async {
    await _config.setMode(mode);
    await retry();
  }

  /// يرجّع الجهاز لشاشة الاختيار الأولى (تغيير السيرفر أو الوضع).
  Future<void> resetConnection() async {
    final s = _current;
    if (s?.api?.token != null) {
      unawaited(s!.api!.post('/api/auth/logout').catchError((_) => <String, dynamic>{}));
    }
    await _config.setToken(null);
    await _config.setServerUrl(null);
    await _config.setMode(null);
    await retry();
  }

  /// بيتأكد إن العنوان ده سيرفر FixTrack قبل ما يحفظه.
  Future<ServerInfo> probeServer(String url) async {
    final api = ApiClient(url);
    try {
      return ServerInfo.fromJson(await api.get('/api/info'));
    } on FormatException {
      throw ApiException('العنوان ده مش سيرفر FixTrack');
    } finally {
      api.close();
    }
  }

  Future<void> connectTo(String url) async {
    final normalized = normalizeServerUrl(url);
    await probeServer(normalized);
    await _config.setMode(AppMode.client);
    await _config.setServerUrl(normalized);
    await _config.setToken(null);
    await retry();
  }

  Future<void> completeSetup(Map<String, String> form) async {
    final api = _current!.api!;
    final res = await api.post('/api/setup', {...form, 'deviceName': _config.deviceName});
    await _config.setToken(res['token'] as String);
    await retry();
  }

  Future<void> login(String username, String password) async {
    final api = _current!.api!;
    final res = await api.post('/api/auth/login', {
      'username': username,
      'password': password,
      'deviceName': _config.deviceName,
    });
    await _config.setToken(res['token'] as String);
    await retry();
  }

  Future<void> logout() async {
    final s = _current;
    try {
      await s?.api?.post('/api/auth/logout');
    } catch (_) {
      // حتى لو السيرفر مش متاح، نخرج من الجهاز ده
    }
    await _config.setToken(null);
    await retry();
  }
}

