import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/realtime.dart';
import '../../core/session.dart';

const _channel = MethodChannel('fixtrack/sms');

class SmsNative {
  static bool get supported => Platform.isAndroid;

  static Future<bool> hasPermission() async => supported && (await _channel.invokeMethod<bool>('hasPermission') ?? false);

  static Future<bool> requestPermission() async =>
      supported && (await _channel.invokeMethod<bool>('requestPermission') ?? false);

  static Future<void> send(String phone, String body) =>
      _channel.invokeMethod<bool>('send', {'phone': phone, 'body': body}).timeout(const Duration(seconds: 60));
}

/// حالة بوابة الـ SMS على الجهاز ده (بتظهر في الإعدادات).
class SmsGatewayState {
  const SmsGatewayState({this.active = false, this.sent = 0, this.failed = 0, this.lastError});
  final bool active;
  final int sent;
  final int failed;
  final String? lastError;
}

/// لو الموبايل ده متفعّل كبوابة SMS: بيسحب الرسائل من طابور السيرفر ويبعتها من الشريحة.
/// شغال طول ما التطبيق مفتوح (حتى لو في الخلفية لفترة).
final smsGatewayProvider = NotifierProvider<SmsGateway, SmsGatewayState>(SmsGateway.new);

class SmsGateway extends Notifier<SmsGatewayState> {
  Timer? _timer;
  bool _running = false;

  @override
  SmsGatewayState build() {
    final session = ref.watch(sessionProvider).value;
    final enabled = SmsNative.supported && ref.read(appConfigProvider).smsGateway;
    ref.onDispose(() => _timer?.cancel());
    if (!enabled || session?.status != SessionStatus.ready) return const SmsGatewayState();

    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _drain());
    ref.listen(realtimeProvider, (_, next) {
      if (next.value?.topic == 'messages') _drain();
    });
    Future.microtask(_drain);
    return const SmsGatewayState(active: true);
  }

  Future<void> setEnabled(bool v) async {
    if (v && !await SmsNative.requestPermission()) {
      throw Exception('لازم توافق على صلاحية إرسال الرسائل عشان البوابة تشتغل');
    }
    await ref.read(appConfigProvider).setSmsGateway(v);
    ref.invalidateSelf();
  }

  Future<void> _drain() async {
    if (_running) return;
    final api = ref.read(sessionProvider).value?.api;
    if (api == null) return;
    _running = true;
    try {
      final device = ref.read(appConfigProvider).deviceName;
      while (true) {
        final res = await api.get('/api/messages/queue', query: {'device': device});
        final list = (res['messages'] as List).cast<Map<String, dynamic>>();
        if (list.isEmpty) break;
        for (final m in list) {
          String? error;
          try {
            await SmsNative.send(m['phone'] as String, m['body'] as String);
          } on PlatformException catch (e) {
            error = e.message ?? e.code;
          } on TimeoutException {
            error = 'الشبكة ما ردتش في الوقت';
          }
          await api.post('/api/messages/${m['id']}/result', {'ok': error == null, 'error': ?error});
          state = SmsGatewayState(
            active: true,
            sent: state.sent + (error == null ? 1 : 0),
            failed: state.failed + (error == null ? 0 : 1),
            lastError: error ?? state.lastError,
          );
        }
      }
    } catch (_) {
      // السيرفر مش متاح دلوقتي، هنحاول تاني في الدورة الجاية
    } finally {
      _running = false;
    }
  }
}
