import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_info.dart';
import '../../core/diagnostics.dart';
import '../../core/file_save.dart';
import '../../widgets/common.dart';

/// سجل المشاكل: التعليق والأخطاء والطلبات البطيئة على الجهاز ده (ولو هو السيرفر، سجل السيرفر كمان).
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  List<File> _files = const [];
  String _text = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = Directory(DiagLog.logsDir((await getApplicationSupportDirectory()).path));
    final files = dir.existsSync() ? (dir.listSync().whereType<File>().where((f) => f.path.contains('.log')).toList()..sort((a, b) => a.path.compareTo(b.path))) : <File>[];
    final buf = StringBuffer();
    for (final f in files) {
      buf.writeln('===== ${f.uri.pathSegments.last} =====');
      final lines = const LineSplitter().convert(f.readAsStringSync());
      buf.writeln(lines.skip(lines.length > 400 ? lines.length - 400 : 0).join('\n'));
    }
    setState(() {
      _files = files;
      _text = buf.toString();
      _loading = false;
    });
  }

  Future<void> _share() async {
    final header = '$appName $appVersion • ${Platform.operatingSystem} ${Platform.operatingSystemVersion}\n\n';
    final bytes = Uint8List.fromList(utf8.encode(header + _text));
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
    final path = await saveOrShareFile(bytes, 'سجل-المشاكل-$stamp.txt', 'text/plain');
    if (path != null && mounted) showMessage(context, 'اتحفظ: $path');
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: const Text('تمسح سجل المشاكل من الجهاز ده؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('امسح')),
        ],
      ),
    );
    if (ok != true) return;
    for (final f in _files) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final freezes = RegExp(r'\[FREEZE\]').allMatches(_text).length;
    final errors = RegExp(r'\[ERROR\]').allMatches(_text).length;
    final slow = RegExp(r'\[SLOW\]').allMatches(_text).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل المشاكل'),
        actions: [
          IconButton(tooltip: 'تحديث', onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
          IconButton(tooltip: 'مسح', onPressed: _files.isEmpty ? null : _clear, icon: const Icon(Icons.delete_outline_rounded)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FilledButton.icon(onPressed: _files.isEmpty ? null : _share, icon: const Icon(Icons.send_rounded), label: const Text('ابعته')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('مفيش مشاكل متسجلة على الجهاز ده ✓'))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(spacing: 8, children: [
                      Chip(avatar: const Icon(Icons.hourglass_bottom_rounded, size: 18), label: Text('تعليق: $freezes')),
                      Chip(avatar: const Icon(Icons.error_outline_rounded, size: 18), label: Text('أخطاء: $errors')),
                      Chip(avatar: const Icon(Icons.speed_rounded, size: 18), label: Text('بطء: $slow')),
                    ]),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('لو البرنامج علّق، دوس "ابعته" وابعت الملف لصاحب البرنامج عشان يعرف السبب بالظبط.'),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(_text, textDirection: TextDirection.rtl, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                      ),
                    ),
                  ),
                ]),
    );
  }
}
