import 'dart:async';
import 'dart:isolate';

import '../core/diagnostics.dart';
import 'api_server.dart';

/// بيشغّل سيرفر المحل في Isolate منفصل عشان الشاشة ما تهنجش أثناء شغل قاعدة البيانات.
///
/// والسيرفر "بيقوم لوحده": أي خطأ مش متوقع بيتسجل من غير ما يوقّع السيرفر، ولو السيرفر وقف فجأة لأي سبب
/// بيرجع يشتغل على نفس البورت في ثانيتين، والأجهزة بترجع تتصل بيه لوحدها.
class ServerHost {
  static int? _port;
  static Future<int>? _starting;
  static Isolate? _isolate;
  static int _restarts = 0;

  static bool get isRunning => _port != null;

  /// عدد المرات اللي السيرفر رجع فيها بعد ما وقف (للاختبارات والسجل).
  static int get restarts => _restarts;

  static Future<int> start(String dataDir, {int port = serverPort}) {
    if (_port != null) return Future.value(_port);
    return _starting ??= _spawn(dataDir, port).then((p) => _port = p).whenComplete(() => _starting = null);
  }

  /// بيوقّف السيرفر غصب (للاختبارات بس): المفروض يرجع لوحده.
  static void debugKill() => _isolate?.kill(priority: Isolate.immediate);

  static Future<int> _spawn(String dataDir, int port) async {
    final ready = ReceivePort();
    final exit = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawn(
      _serverMain,
      [ready.sendPort, dataDir, port],
      debugName: 'fixtrack-server',
      // خطأ في حتة مش هيوقّع السيرفر كله، بيتسجل بس
      errorsAreFatal: false,
      onExit: exit.sendPort,
      onError: errors.sendPort,
    );
    final msg = await ready.first;
    if (msg is! int) {
      exit.close();
      errors.close();
      throw ServerStartException(msg.toString());
    }
    _isolate = isolate;
    final log = DiagLog.openIn(dataDir, 'server');
    errors.listen((e) {
      final parts = e is List ? e : [e];
      log.write('ERROR', 'خطأ في السيرفر (اتسجل والسيرفر كمّل): ${parts.first}${parts.length > 1 ? '\n    ${'${parts[1]}'.split('\n').take(6).join('\n    ')}' : ''}');
    });
    exit.listen((_) async {
      exit.close();
      errors.close();
      _isolate = null;
      log.write('ERROR', 'السيرفر وقف فجأة، وبيرجع يشتغل لوحده');
      for (var attempt = 1; attempt <= 60; attempt++) {
        await Future<void>.delayed(Duration(seconds: attempt == 1 ? 2 : 5));
        try {
          _port = await _spawn(dataDir, port);
          _restarts++;
          log.write('INFO', 'السيرفر رجع اشتغل (محاولة $attempt)');
          return;
        } catch (e) {
          log.write('ERROR', 'محاولة رجوع السيرفر رقم $attempt ما نجحتش: $e');
        }
      }
    });
    return msg;
  }
}

class ServerStartException implements Exception {
  ServerStartException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<void> _serverMain(List<Object> args) async {
  final ready = args[0] as SendPort;
  try {
    final server = FixTrackServer(dataDir: args[1] as String, requestedPort: args[2] as int);
    await server.start();
    ready.send(server.port);
  } on ApiError catch (e) {
    ready.send(e.message);
  } catch (e) {
    ready.send('السيرفر ما اشتغلش: $e');
  }
}
