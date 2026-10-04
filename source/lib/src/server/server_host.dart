import 'dart:isolate';

import 'api_server.dart';

/// بيشغّل سيرفر المحل في Isolate منفصل عشان الشاشة ما تهنجش أثناء شغل قاعدة البيانات.
class ServerHost {
  static int? _port;
  static Future<int>? _starting;

  static bool get isRunning => _port != null;

  static Future<int> start(String dataDir) {
    if (_port != null) return Future.value(_port);
    return _starting ??= _spawn(dataDir).then((port) => _port = port).whenComplete(() => _starting = null);
  }

  static Future<int> _spawn(String dataDir) async {
    final ready = ReceivePort();
    await Isolate.spawn(_serverMain, [ready.sendPort, dataDir], debugName: 'fixtrack-server');
    final msg = await ready.first;
    if (msg is int) return msg;
    throw ServerStartException(msg.toString());
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
    final server = FixTrackServer(dataDir: args[1] as String);
    await server.start();
    ready.send(server.port);
  } on ApiError catch (e) {
    ready.send(e.message);
  } catch (e) {
    ready.send('السيرفر ما اشتغلش: $e');
  }
}
