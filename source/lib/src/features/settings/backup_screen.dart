import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../tickets/providers.dart';

final _backupsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => apiOf(ref).get('/api/backups'));

/// النسخ الاحتياطي: بيتعمل لوحده كل يوم، وتقدر تعمله يدوي أو ترجّع نسخة قديمة.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(_backupsProvider);
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder(String? current) async {
    final isServer = ref.read(appConfigProvider).mode == AppMode.server;
    String? path;
    if (isServer) {
      path = await getDirectoryPath(confirmButtonText: 'اختيار الفولدر');
    } else {
      final c = TextEditingController(text: current);
      path = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('فولدر النسخ على كمبيوتر السيرفر'),
          content: TextField(controller: c, textDirection: TextDirection.ltr, decoration: const InputDecoration(hintText: r'D:\Backups')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('حفظ')),
          ],
        ),
      );
    }
    if (path == null || !mounted) return;
    await _run(
      () => ref.read(sessionProvider).value!.api!.patch('/api/backups/settings', {'backupDir': path}),
      'هيتعمل نسخة في الفولدر ده كل يوم',
    );
  }

  Future<void> _restore(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: brandOrange, size: 40),
        title: const Text('ترجيع نسخة قديمة؟'),
        content: Text('كل البيانات هترجع زي ما كانت وقت النسخة ($name)، وأي حاجة اتسجلت بعدها هتروح.\n'
            'البرنامج هيحتفظ بنسخة من البيانات الحالية للاحتياط.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: brandOrange), onPressed: () => Navigator.pop(context, true), child: const Text('ترجيع')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(sessionProvider).value!.api!.post('/api/backups/restore', {'name': name}),
      'اقفل البرنامج على كمبيوتر السيرفر وافتحه تاني عشان الترجيع يتم',
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_backupsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorBanner(errorText(e))),
        data: (d) {
          final last = parseDate(d['lastBackupAt']);
          final err = (d['lastBackupError'] as String?)?.isEmpty ?? true ? null : d['lastBackupError'] as String;
          final external = (d['backupDir'] as String?)?.isEmpty ?? true ? null : d['backupDir'] as String;
          final backups = (d['backups'] as List).cast<Map<String, dynamic>>();
          return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
            if (d['restorePending'] == true)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: ErrorBanner('فيه ترجيع مستني: اقفل البرنامج على كمبيوتر السيرفر وافتحه تاني.')),
            SectionCard(title: 'الحالة', icon: Icons.shield_rounded, children: [
              Text(last == null ? 'لسه ما اتعملش نسخة' : 'آخر نسخة: ${formatDateTime(last)} (${timeAgo(last)})', style: const TextStyle().semiBold),
              const SizedBox(height: 4),
              const Text('البرنامج بيعمل نسخة لوحده كل يوم، وبيحتفظ بآخر 14 نسخة.'),
              if (err != null) ...[const SizedBox(height: 8), ErrorBanner(err)],
              const SizedBox(height: 12),
              BusyButton(
                label: 'اعمل نسخة دلوقتي',
                icon: Icons.backup_rounded,
                busy: _busy,
                onPressed: () => _run(() => ref.read(sessionProvider).value!.api!.post('/api/backups'), 'اتعملت نسخة'),
              ),
            ]),
            const SizedBox(height: 12),
            SectionCard(title: 'نسخة في مكان تاني', icon: Icons.folder_copy_rounded, children: [
              const Text('لو الكمبيوتر باظ أو اتسرق، النسخ اللي عليه هتضيع معاه. اختار فولدر تاني يتحفظ فيه نسخة كمان:\n'
                  '• فلاشة أو هارد خارجي\n'
                  '• أو فولدر Google Drive على الكمبيوتر (لو مسطب Google Drive) عشان النسخة تبقى على النت ببلاش'),
              const SizedBox(height: 12),
              if (external != null) Text(external, textDirection: TextDirection.ltr, style: TextStyle(color: scheme.primary).semiBold),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _chooseFolder(external),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(external == null ? 'اختيار فولدر' : 'تغيير'),
                ),
                if (external != null)
                  TextButton(
                    onPressed: _busy ? null : () => _run(() => ref.read(sessionProvider).value!.api!.patch('/api/backups/settings', {'backupDir': null}), 'اتلغى الفولدر التاني'),
                    child: const Text('إلغاء'),
                  ),
              ]),
            ]),
            const SizedBox(height: 12),
            SectionCard(title: 'النسخ المحفوظة', icon: Icons.history_rounded, children: [
              Text(d['localPath'] as String? ?? '', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              for (final b in backups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_rounded),
                  title: Text(formatDateTime(parseDate(b['createdAt'])!)),
                  subtitle: Text('${((b['size'] as int) / 1024 / 1024).toStringAsFixed(1)} ميجا'),
                  trailing: TextButton(onPressed: _busy ? null : () => _restore(b['name'] as String), child: const Text('ترجيع')),
                ),
              if (backups.isEmpty) const Text('مفيش نسخ لسه'),
            ]),
          ]);
        },
      ),
    );
  }
}
