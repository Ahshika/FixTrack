import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// سجل المشاكل: ملف نصي صغير في فولدر البرنامج (logs). لما يعدّي 1 ميجا بيتنقل لنسخة قديمة (.1).
/// من غير Flutter عشان السيرفر (اللي في Isolate لوحده) يستخدمه كمان.
class DiagLog {
  DiagLog(this.path);
  final String path;

  static DiagLog? app;

  static DiagLog openIn(String dataDir, String name) {
    final dir = Directory('$dataDir${Platform.pathSeparator}logs')..createSync(recursive: true);
    return DiagLog('${dir.path}${Platform.pathSeparator}$name.log');
  }

  static String logsDir(String dataDir) => '$dataDir${Platform.pathSeparator}logs';

  void write(String level, String message) {
    try {
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 1024 * 1024) {
        final old = File('$path.1');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp = '${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
      File(path).writeAsStringSync('$stamp [$level] $message\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // السجل عمره ما يوقّع البرنامج
    }
  }

  void error(Object e, [StackTrace? st]) {
    final stack = st?.toString().split('\n').where((l) => l.trim().isNotEmpty).take(8).join('\n    ');
    write('ERROR', '$e${stack == null ? '' : '\n    $stack'}');
  }
}

/// مراقب التعليق: Isolate صغير شغال لوحده بيستنى "نبضة" من الشاشة كل ثانية.
/// لو الشاشة وقفت 4 ثواني أو أكتر بيكتب في السجل إمتى وقد إيه وآخر حاجة اتعملت قبلها.
class FreezeWatchdog {
  static SendPort? _port;
  static String _last = 'فتح البرنامج';
  static Timer? _beat;

  /// آخر حاجة المستخدم عملها (شاشة اتفتحت، أو طلب للسيرفر).
  static void action(String what) => _last = what;

  static Future<void> start(String logPath) async {
    if (_port != null) return;
    final ready = ReceivePort();
    await Isolate.spawn(_watch, [ready.sendPort, logPath], debugName: 'freeze-watchdog');
    _port = await ready.first as SendPort;
    _beat = Timer.periodic(const Duration(seconds: 1), (_) => _port?.send(_last));
  }

  /// البرنامج اتصغّر أو الموبايل قفل الشاشة: مش تعليق.
  static void paused(bool value) => _port?.send(value ? '\u0000pause' : '\u0000resume');

  static void stop() {
    _beat?.cancel();
    _port = null;
  }
}

void _watch(List<Object> args) {
  final out = args[0] as SendPort;
  final log = DiagLog(args[1] as String);
  final inbox = ReceivePort();
  out.send(inbox.sendPort);
  var lastBeat = DateTime.now();
  var lastAction = '';
  var paused = false;
  DateTime? frozenSince;

  inbox.listen((m) {
    final now = DateTime.now();
    if (m == '\u0000pause') {
      paused = true;
      return;
    }
    if (m == '\u0000resume') {
      paused = false;
      lastBeat = now;
      return;
    }
    if (frozenSince != null) {
      log.write('FREEZE', 'الشاشة رجعت تشتغل بعد ${now.difference(frozenSince!).inSeconds} ثانية تعليق. آخر حاجة قبل التعليق: $lastAction');
      frozenSince = null;
    }
    lastBeat = now;
    lastAction = m as String;
  });

  Timer.periodic(const Duration(seconds: 1), (_) {
    if (paused || frozenSince != null) return;
    final gap = DateTime.now().difference(lastBeat);
    if (gap.inSeconds >= 4) {
      frozenSince = lastBeat;
      log.write('FREEZE', 'الشاشة واقفة من ${gap.inSeconds} ثواني. آخر حاجة: $lastAction');
    }
  });
}
