// FixTrack License Maker: برنامج صاحب FixTrack لعمل أكواد التفعيل للمحلات.
// محتاج ملف المفتاح السري (license-private.key) اللي في فولدر signing. ماتدّيش البرنامج ده أو المفتاح لحد.
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
// ignore: implementation_imports
import 'package:fixtrack/src/core/license.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const MakerApp());

const _blue = Color(0xFF1B4FD8);
const _orange = Color(0xFFFF7A1A);

class MakerApp extends StatelessWidget {
  const MakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FixTrack License Maker',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Cairo',
        colorScheme: ColorScheme.fromSeed(seedColor: _blue, secondary: _orange),
        inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
      ),
      home: const MakerHome(),
    );
  }
}

/// سجل الأكواد اللي اتعملت (بيتحفظ عندك بس).
class IssuedLicense {
  IssuedLicense(this.j);
  final Map<String, dynamic> j;
  String get shop => j['shop'] as String;
  String get phone => j['phone'] as String? ?? '';
  String get device => j['device'] as String;
  String get plan => j['plan'] as String;
  DateTime? get expires => j['expires'] == null ? null : DateTime.parse(j['expires'] as String);
  DateTime get issued => DateTime.parse(j['issued'] as String);
  String get code => j['code'] as String;
}

class MakerHome extends StatefulWidget {
  const MakerHome({super.key});

  @override
  State<MakerHome> createState() => _MakerHomeState();
}

class _MakerHomeState extends State<MakerHome> {
  Directory? _dir;
  List<int>? _seed;
  String? _keyPath;
  final _history = <IssuedLicense>[];

  final _shop = TextEditingController();
  final _phone = TextEditingController();
  final _device = TextEditingController();
  final _months = TextEditingController(text: '12');
  String _plan = 'yearly';
  int _devices = 3;
  int _branches = 1;
  String? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}data')..createSync(recursive: true);
    final cfg = File('${dir.path}${Platform.pathSeparator}config.json');
    String? keyPath;
    if (cfg.existsSync()) keyPath = (jsonDecode(cfg.readAsStringSync()) as Map)['keyPath'] as String?;
    if (keyPath != null && !File(keyPath).existsSync()) keyPath = null;
    // الافتراضي: فولدر signing في أي فولدر فوق البرنامج (Fix Track\signing)
    keyPath ??= _guessKeyPath();
    final hist = File('${dir.path}${Platform.pathSeparator}licenses.json');
    setState(() {
      _dir = dir;
      if (hist.existsSync()) {
        _history
          ..clear()
          ..addAll((jsonDecode(hist.readAsStringSync()) as List).map((j) => IssuedLicense(j as Map<String, dynamic>)));
      }
    });
    if (keyPath != null) _useKey(keyPath);
  }

  String? _guessKeyPath() {
    var d = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) {
      final f = File('${d.path}${Platform.pathSeparator}signing${Platform.pathSeparator}license-private.key');
      if (f.existsSync()) return f.path;
      d = d.parent;
    }
    return null;
  }

  void _useKey(String path) {
    try {
      final seed = base64.decode(File(path).readAsStringSync().trim());
      if (seed.length != 32) throw const FormatException();
      File('${_dir!.path}${Platform.pathSeparator}config.json').writeAsStringSync(jsonEncode({'keyPath': path}));
      setState(() {
        _seed = seed;
        _keyPath = path;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'ملف المفتاح مش صحيح: $path');
    }
  }

  Future<void> _pickKey() async {
    final f = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'Key', extensions: ['key'])]);
    if (f != null) _useKey(f.path);
  }

  void _saveHistory() {
    File('${_dir!.path}${Platform.pathSeparator}licenses.json').writeAsStringSync(jsonEncode([for (final h in _history) h.j]));
  }

  Future<void> _generate() async {
    final device = _device.text.trim().toUpperCase().replaceAll(' ', '');
    final normalized = device.length == 10 ? '${device.substring(0, 5)}-${device.substring(5)}' : device;
    if (!RegExp(r'^[A-Z2-9]{5}-[A-Z2-9]{5}$').hasMatch(normalized)) {
      setState(() => _error = 'كود الجهاز لازم يكون زي كده: ABCDE-FGH23');
      return;
    }
    if (_shop.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم المحل');
      return;
    }
    final now = DateTime.now();
    final months = switch (_plan) {
      'monthly' => 1,
      'yearly' => 12,
      'lifetime' => null,
      _ => int.tryParse(_months.text.trim()) ?? 1,
    };
    final expires = months == null ? null : DateTime(now.year, now.month + months, now.day, 23, 59);
    final data = LicenseData(
      id: 'L${now.millisecondsSinceEpoch}',
      shop: _shop.text.trim(),
      device: normalized,
      plan: _plan,
      expires: expires,
      devices: _devices,
      branches: _branches,
      issued: now,
    );
    final code = await signLicense(data, _seed!);
    // نتأكد إن الكود هيشتغل في برنامج المحلات (بالمفتاح العام اللي جواه)
    try {
      await verifyLicense(code, deviceCode: normalized);
    } on LicenseException {
      setState(() => _error = 'ملف المفتاح ده مش هو المفتاح بتاع FixTrack. الكود مش هيشتغل عند المحل.');
      return;
    }
    _history.insert(0, IssuedLicense({
      'shop': data.shop,
      'phone': _phone.text.trim(),
      'device': normalized,
      'plan': _plan,
      'expires': expires?.toIso8601String(),
      'issued': now.toIso8601String(),
      'devices': _devices,
      'branches': _branches,
      'code': code,
    }));
    _saveHistory();
    setState(() {
      _code = code;
      _error = null;
    });
  }

  String _planLabel(String p) => const {'monthly': 'شهري', 'yearly': 'سنوي', 'lifetime': 'مدى الحياة', 'custom': 'شهور'}[p] ?? p;

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<void> _whatsapp(String phone, String code) async {
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('0') && d.length == 11) d = '20${d.substring(1)}';
    final msg = 'كود تفعيل FixTrack:\n$code\n\nمن البرنامج: الإعدادات ← الاشتراك ← الصق الكود ← تفعيل';
    await launchUrl(Uri.parse('https://wa.me/$d?text=${Uri.encodeComponent(msg)}'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FixTrack • أكواد التفعيل'),
        actions: [
          TextButton.icon(onPressed: _pickKey, icon: const Icon(Icons.key_rounded), label: Text(_seed == null ? 'اختار ملف المفتاح' : 'المفتاح موجود ✓')),
          const SizedBox(width: 8),
        ],
      ),
      body: _seed == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.key_off_rounded, size: 56),
                const SizedBox(height: 12),
                const Text('اختار ملف license-private.key من فولدر signing'),
                const SizedBox(height: 12),
                FilledButton(onPressed: _pickKey, child: const Text('اختيار الملف')),
                if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              ]),
            )
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 460,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text('كود تفعيل جديد', style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(controller: _shop, decoration: const InputDecoration(labelText: 'اسم المحل')),
                  const SizedBox(height: 12),
                  TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'واتساب المحل (عشان تبعتله الكود)')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _device,
                    textDirection: TextDirection.ltr,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'كود الجهاز (الإعدادات ← الاشتراك عند المحل)', hintText: 'ABCDE-FGH23'),
                  ),
                  const SizedBox(height: 16),
                  const Text('مدة الاشتراك'),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final p in const ['monthly', 'yearly', 'lifetime', 'custom'])
                      ChoiceChip(label: Text(_planLabel(p)), selected: _plan == p, onSelected: (_) => setState(() => _plan = p)),
                  ]),
                  if (_plan == 'custom') ...[
                    const SizedBox(height: 8),
                    TextField(controller: _months, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد الشهور')),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    const Expanded(child: Text('عدد الأجهزة (كمبيوتر + موبايلات)')),
                    IconButton(onPressed: () => setState(() => _devices = (_devices - 1).clamp(1, 50)), icon: const Icon(Icons.remove)),
                    Text('$_devices', style: text.titleMedium),
                    IconButton(onPressed: () => setState(() => _devices = (_devices + 1).clamp(1, 50)), icon: const Icon(Icons.add)),
                  ]),
                  Row(children: [
                    const Expanded(child: Text('عدد الفروع')),
                    IconButton(onPressed: () => setState(() => _branches = (_branches - 1).clamp(1, 50)), icon: const Icon(Icons.remove)),
                    Text('$_branches', style: text.titleMedium),
                    IconButton(onPressed: () => setState(() => _branches = (_branches + 1).clamp(1, 50)), icon: const Icon(Icons.add)),
                  ]),
                  const SizedBox(height: 12),
                  if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  FilledButton.icon(onPressed: _generate, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('اعمل الكود')),
                  if (_code != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: _blue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: SelectableText(_code!, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _code!));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اتنسخ الكود')));
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('نسخ'),
                      ),
                      if (_phone.text.trim().isNotEmpty)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                          onPressed: () => _whatsapp(_phone.text, _code!),
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('ابعته واتساب'),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Text('المفتاح: $_keyPath', style: text.bodySmall, textDirection: TextDirection.ltr),
                ]),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text('الأكواد اللي اتعملت (${_history.length})', style: text.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_history.isEmpty) const Text('لسه ما عملتش أكواد'),
                  for (final h in _history)
                    Card(
                      child: ListTile(
                        title: Text('${h.shop} • ${_planLabel(h.plan)}'),
                        subtitle: Text('${h.device} • اتعمل ${_fmt(h.issued)}${h.phone.isNotEmpty ? ' • ${h.phone}' : ''}'),
                        trailing: Text(
                          h.expires == null ? 'مدى الحياة' : 'لحد ${_fmt(h.expires!)}',
                          style: TextStyle(
                            color: h.expires != null && h.expires!.difference(DateTime.now()).inDays < 10 ? _orange : null,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: h.code));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('اتنسخ كود ${h.shop}')));
                        },
                      ),
                    ),
                ]),
              ),
            ]),
    );
  }
}
