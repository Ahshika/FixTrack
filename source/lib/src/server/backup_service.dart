part of 'api_server.dart';

const _keepBackups = 14;

/// نسخ احتياطي أوتوماتيك كل يوم: قاعدة البيانات + الصور + اللوجو في ملف zip واحد.
/// بيتحفظ في فولدر البرنامج، ونسخة كمان في فولدر تاني لو المحل اختاره
/// (فلاشة، أو هارد تاني، أو فولدر Google Drive على الكمبيوتر عشان يبقى على النت ببلاش).
extension _BackupRoutes on FixTrackServer {
  void _registerBackupRoutes(Router r) {
    r.get('/api/backups', _authed(_listBackups, only: {'owner'}));
    r.post('/api/backups', _authed((req, u) async {
      final name = await _createBackup(manual: true);
      _audit(u.id, 'backup.create', 'backup', null, name);
      return _listBackups(req, u);
    }, only: {'owner'}));
    r.patch('/api/backups/settings', _authed(_backupSettings, only: {'owner'}));
    r.post('/api/backups/restore', _authed(_stageRestore, only: {'owner'}));
  }

  Directory get _backupDir => Directory(p.join(dataDir, 'backups'))..createSync(recursive: true);

  Object? _listBackups(Request req, AuthUser u) {
    final files = _backupDir.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return {
      'backups': files
          .map((f) => {'name': p.basename(f.path), 'size': f.lengthSync(), 'createdAt': f.lastModifiedSync().toUtc().toIso8601String()})
          .toList(),
      'backupDir': db.setting('backup_dir'),
      'lastBackupAt': db.setting('last_backup_at'),
      'lastBackupError': db.setting('last_backup_error'),
      'localPath': _backupDir.path,
      'restorePending': File(p.join(dataDir, 'restore.pending')).existsSync(),
    };
  }

  Future<Object?> _backupSettings(Request req, AuthUser u) async {
    final body = await _body(req);
    final dir = _optionalText(body, 'backupDir');
    if (dir != null && !Directory(dir).existsSync()) throw ApiError(400, 'الفولدر ده مش موجود على كمبيوتر السيرفر');
    db.setSetting('backup_dir', dir ?? '');
    if (dir != null) await _createBackup(manual: true);
    return _listBackups(req, u);
  }

  /// بيعمل نسخة لو آخر نسخة عدّى عليها أكتر من 20 ساعة.
  Future<void> _runBackupIfDue() async {
    try {
      final last = DateTime.tryParse(db.setting('last_backup_at') ?? '');
      if (last != null && DateTime.now().toUtc().difference(last).inHours < 20) return;
      if (db.selectOne('SELECT id FROM shop LIMIT 1') == null) return;
      await _createBackup();
    } catch (e) {
      db.setSetting('last_backup_error', '$e');
    }
  }

  Future<String> _createBackup({bool manual = false}) async {
    final stamp = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'fixtrack-${stamp.year}-${two(stamp.month)}-${two(stamp.day)}-${two(stamp.hour)}${two(stamp.minute)}.zip';

    // نسخة متسقة من قاعدة البيانات حتى لو فيه شغل شغال
    final snapshot = File(p.join(_backupDir.path, '.snapshot.db'));
    if (snapshot.existsSync()) snapshot.deleteSync();
    db.raw.execute('VACUUM INTO ?', [snapshot.path]);

    final info = jsonEncode({'app': 'fixtrack', 'version': appVersion, 'createdAt': stamp.toUtc().toIso8601String(), 'serverId': db.setting('server_id')});
    final outPath = p.join(_backupDir.path, name);
    final snapshotPath = snapshot.path, data = dataDir;
    // الضغط بيحصل في Isolate لوحده: السيرفر يفضل يرد على الأجهزة، ومن غير ما الصور كلها تتحمّل في الذاكرة
    await backupInBackground(outPath, snapshotPath, 'fixtrack.db', data, info);
    final out = File(outPath);
    snapshot.deleteSync();

    // نسخة في الفولدر التاني (لو المحل اختاره)
    final external = db.setting('backup_dir');
    String? externalError;
    if (external != null && external.isNotEmpty) {
      try {
        final dir = Directory(p.join(external, 'FixTrack Backups'))..createSync(recursive: true);
        out.copySync(p.join(dir.path, name));
        final old = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()..sort((a, b) => b.path.compareTo(a.path));
        for (final f in old.skip(_keepBackups * 2)) {
          f.deleteSync();
        }
      } catch (e) {
        externalError = 'مش قادر أحفظ في الفولدر التاني: $e';
      }
    }

    final local = _backupDir.listSync().whereType<File>().where((f) => f.path.endsWith('.zip')).toList()..sort((a, b) => b.path.compareTo(a.path));
    for (final f in local.skip(_keepBackups)) {
      f.deleteSync();
    }
    db.setSetting('last_backup_at', nowIso());
    db.setSetting('last_backup_error', externalError ?? '');
    return name;
  }

  /// الاسترجاع بيحصل وقت ما البرنامج يتفتح تاني (عشان قاعدة البيانات مش مفتوحة).
  Future<Object?> _stageRestore(Request req, AuthUser u) async {
    final body = await _body(req);
    final name = p.basename(body['name'] as String? ?? '');
    final file = File(p.join(_backupDir.path, name));
    if (!name.endsWith('.zip') || !file.existsSync()) throw ApiError(404, 'النسخة دي مش موجودة');
    final valid = await zipHasFile(file.path, 'fixtrack.db');
    if (!valid) throw ApiError(400, 'الملف ده مش نسخة احتياطية من FixTrack');
    File(p.join(dataDir, 'restore.pending')).writeAsStringSync(file.path);
    _audit(u.id, 'backup.restore', 'backup', null, name);
    return {'ok': true, 'message': 'اقفل البرنامج على كمبيوتر السيرفر وافتحه تاني عشان الاسترجاع يتم'};
  }
}

/// بيتنفذ قبل فتح قاعدة البيانات: لو فيه استرجاع مستني، بيحط النسخة مكان البيانات الحالية
/// (وبيحتفظ بنسخة من البيانات الحالية للاحتياط).
void applyPendingRestore(String dataDir) {
  final pending = File(p.join(dataDir, 'restore.pending'));
  if (!pending.existsSync()) return;
  final zip = File(pending.readAsStringSync().trim());
  pending.deleteSync();
  if (!zip.existsSync()) return;
  final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
  final dbFile = File(p.join(dataDir, 'fixtrack.db'));
  if (dbFile.existsSync()) {
    final safety = Directory(p.join(dataDir, 'backups'))..createSync(recursive: true);
    dbFile.copySync(p.join(safety.path, 'before-restore-${DateTime.now().millisecondsSinceEpoch}.db'));
  }
  for (final suffix in ['-wal', '-shm']) {
    final f = File('${dbFile.path}$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  for (final entry in archive.files) {
    if (!entry.isFile || entry.name == 'backup.json') continue;
    final target = p.normalize(p.join(dataDir, entry.name));
    if (!p.isWithin(dataDir, target)) continue; // حماية من ملفات zip فيها مسارات برا الفولدر
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(entry.content as List<int>);
  }
}

Future<void> backupInBackground(String outPath, String snapshotPath, String dbName, String dataDir, String infoJson) =>
    Isolate.run(() => writeBackupZip(outPath, snapshotPath, dbName, dataDir, infoJson));

Future<bool> zipHasFile(String zipPath, String name) => Isolate.run(() {
      final input = InputFileStream(zipPath);
      try {
        return ZipDecoder().decodeStream(input).findFile(name) != null;
      } finally {
        input.closeSync();
      }
    });

/// بيكتب ملف النسخة الاحتياطية على الديسك مباشرة (بيتنادى في Isolate لوحده).
Future<void> writeBackupZip(String outPath, String snapshotPath, String dbName, String dataDir, String infoJson) async {
  final enc = ZipFileEncoder()..create(outPath);
  await enc.addFile(File(snapshotPath), dbName);
  final logo = File(p.join(dataDir, 'logo.png'));
  if (logo.existsSync()) await enc.addFile(logo, 'logo.png');
  final files = Directory(p.join(dataDir, 'files'));
  if (files.existsSync()) {
    for (final f in files.listSync().whereType<File>()) {
      await enc.addFile(f, 'files/${p.basename(f.path)}');
    }
  }
  final info = utf8.encode(infoJson);
  enc.addArchiveFile(ArchiveFile('backup.json', info.length, info));
  await enc.close();
}
