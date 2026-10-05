import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fixtrack/src/core/diagnostics.dart';

void main() {
  test('the watchdog records a UI freeze and when it recovered', () async {
    final dir = await Directory.systemTemp.createTemp('diag_test');
    final log = DiagLog.openIn(dir.path, 'app');
    FreezeWatchdog.action('POST /api/checks/1/orders');
    await FreezeWatchdog.start(log.path);
    await Future<void>.delayed(const Duration(seconds: 2));
    // تعليق مقصود: الشاشة (الـ Isolate الأساسي) واقفة 6 ثواني
    sleep(const Duration(seconds: 6));
    await Future<void>.delayed(const Duration(seconds: 3));
    FreezeWatchdog.stop();
    final text = File(log.path).readAsStringSync();
    expect(RegExp(r'\[FREEZE\] الشاشة واقفة').hasMatch(text), true, reason: text);
    expect(RegExp(r'\[FREEZE\] الشاشة رجعت تشتغل بعد [5-7] ثانية').hasMatch(text), true, reason: text);
    expect(text, contains('POST /api/checks/1/orders'));
    await dir.delete(recursive: true);
  });

  test('the log rotates after 1 MB', () async {
    final dir = await Directory.systemTemp.createTemp('diag_rot');
    final log = DiagLog.openIn(dir.path, 'app');
    File(log.path).writeAsStringSync('x' * (1024 * 1024 + 10));
    log.write('INFO', 'جديد');
    expect(File('${log.path}.1').existsSync(), true);
    expect(File(log.path).readAsStringSync(), contains('جديد'));
    await dir.delete(recursive: true);
  });
}
