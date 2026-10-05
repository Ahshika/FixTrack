import 'package:file_selector/file_selector.dart';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/spreadsheet.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../pos/providers.dart';

/// الحقول اللي ممكن تتقرأ من ملف البرنامج القديم.
const _fields = {
  'name': 'اسم الصنف *',
  'barcode': 'الباركود',
  'category': 'القسم',
  'price': 'سعر البيع',
  'cost': 'سعر الشرا',
  'qty': 'الكمية',
  'lowStock': 'حد التنبيه',
};

/// كلمات بتتعرّف بيها الأعمدة لوحدها (عربي وإنجليزي).
const _guesses = {
  'name': ['اسم', 'الصنف', 'صنف', 'item', 'name', 'product', 'البيان', 'الوصف'],
  'barcode': ['باركود', 'الباركود', 'barcode', 'كود', 'code', 'sku'],
  'category': ['قسم', 'القسم', 'مجموعة', 'category', 'group', 'النوع'],
  'price': ['سعر البيع', 'البيع', 'price', 'sale', 'selling', 'سعر'],
  'cost': ['سعر الشراء', 'سعر الشرا', 'الشراء', 'الشرا', 'التكلفة', 'cost', 'purchase'],
  'qty': ['كمية', 'الكمية', 'الرصيد', 'رصيد', 'qty', 'quantity', 'stock', 'العدد'],
  'lowStock': ['حد الطلب', 'حد التنبيه', 'الحد الأدنى', 'min', 'reorder'],
};

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  String? _fileName;
  List<List<String>> _rows = [];
  bool _hasHeader = true;
  final Map<String, int?> _map = {for (final k in _fields.keys) k: null};
  bool _updateQty = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  int get _columns => _rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  List<List<String>> get _dataRows => _hasHeader && _rows.isNotEmpty ? _rows.sublist(1) : _rows;

  Future<void> _pick() async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'Excel / CSV', extensions: ['xlsx', 'csv', 'txt', 'xls']),
    ]);
    if (file == null) return;
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final raw = await file.readAsBytes();
      final fileName = file.name;
      // ملف Excel كبير بياخد وقت في القراءة، فبيتقري في Isolate لوحده عشان الشاشة ما تقفش
      final rows = await Isolate.run(() => SpreadsheetReader.read(raw, fileName));
      if (rows.isEmpty) throw const FormatException('الملف فاضي');
      setState(() {
        _fileName = file.name;
        _rows = rows;
        _autoMap();
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'مش قادر أقرا الملف: $e');
    }
  }

  void _autoMap() {
    for (final k in _map.keys) {
      _map[k] = null;
    }
    if (_rows.isEmpty) return;
    final header = _rows.first.map((h) => h.trim().toLowerCase()).toList();
    final used = <int>{};
    // الأطول الأول عشان "سعر الشرا" مايتاخدش على إنه "سعر"
    final pairs = [
      for (final e in _guesses.entries)
        for (final w in e.value) (field: e.key, word: w),
    ]..sort((a, b) => b.word.length.compareTo(a.word.length));
    for (final pair in pairs) {
      if (_map[pair.field] != null) continue;
      for (var i = 0; i < header.length; i++) {
        if (!used.contains(i) && header[i].contains(pair.word)) {
          _map[pair.field] = i;
          used.add(i);
          break;
        }
      }
    }
    _hasHeader = _map.values.any((v) => v != null);
  }

  String _cell(List<String> row, String field) {
    final i = _map[field];
    return i == null || i >= row.length ? '' : row[i];
  }

  Future<void> _import() async {
    if (_map['name'] == null) {
      setState(() => _error = 'لازم تحدد عمود اسم الصنف');
      return;
    }
    int? cents(String v) => v.isEmpty ? null : parseMoney(v);
    int? whole(String v) {
      final d = double.tryParse(latinDigits(v).replaceAll(',', ''));
      return d?.round();
    }

    final rows = [
      for (final r in _dataRows)
        {
          'name': _cell(r, 'name'),
          'barcode': _cell(r, 'barcode'),
          'category': _cell(r, 'category').isEmpty ? null : _cell(r, 'category'),
          'priceCents': cents(_cell(r, 'price')),
          'costCents': cents(_cell(r, 'cost')),
          'qty': _map['qty'] == null ? null : whole(_cell(r, 'qty')),
          'lowStock': _map['lowStock'] == null ? null : whole(_cell(r, 'lowStock')),
        },
    ];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(sessionProvider).value!.api!;
      var created = 0, updated = 0;
      final errors = <String>[];
      for (var i = 0; i < rows.length; i += 1000) {
        final res = await api.send('POST', '/api/products/import',
            body: {'rows': rows.sublist(i, (i + 1000).clamp(0, rows.length)), 'updateQty': _updateQty}, timeout: const Duration(minutes: 2));
        created += res['created'] as int;
        updated += res['updated'] as int;
        errors.addAll((res['errors'] as List).cast<String>());
      }
      ref.invalidate(productsProvider);
      setState(() => _result = {'created': created, 'updated': updated, 'errors': errors});
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد الأصناف من Excel')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          SectionCard(
            title: '1. اختار الملف',
            icon: Icons.upload_file_rounded,
            children: [
              const Text('من برنامجك القديم، طلّع الأصناف في ملف Excel (xlsx) أو CSV، وبعدين اختاره هنا.\n'
                  'لو الأصناف موجودة قبل كده (نفس الباركود) هتتحدث، والجديدة هتتضاف.'),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.folder_open_rounded), label: const Text('اختيار ملف')),
                const SizedBox(width: 12),
                if (_fileName != null) Expanded(child: Text('$_fileName • ${_dataRows.length} صف', overflow: TextOverflow.ellipsis)),
              ]),
            ],
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: '2. حدد كل عمود فيه إيه',
              icon: Icons.view_column_rounded,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _hasHeader,
                  onChanged: (v) => setState(() => _hasHeader = v ?? true),
                  title: const Text('أول صف فيه أسماء الأعمدة (مش صنف)'),
                ),
                LayoutBuilder(builder: (context, c) {
                  final w = c.maxWidth >= 700 ? (c.maxWidth - 24) / 3 : c.maxWidth >= 460 ? (c.maxWidth - 12) / 2 : c.maxWidth;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final f in _fields.entries)
                      SizedBox(
                        width: w,
                        child: DropdownButtonFormField<int?>(
                          initialValue: _map[f.key],
                          isExpanded: true,
                          decoration: InputDecoration(labelText: f.value),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('— مش موجود —')),
                            for (var i = 0; i < _columns; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text(
                                  _hasHeader && i < _rows.first.length && _rows.first[i].isNotEmpty ? _rows.first[i] : 'عمود ${i + 1}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) => setState(() => _map[f.key] = v),
                        ),
                      ),
                  ]);
                }),
                if (_map['qty'] != null)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _updateQty,
                    onChanged: (v) => setState(() => _updateQty = v ?? true),
                    title: const Text('خلّي الكميات زي اللي في الملف (للأصناف الموجودة كمان)'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '3. راجع أول الصفوف',
              icon: Icons.preview_rounded,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: const TextStyle().bold,
                    columns: [for (final f in _fields.entries.where((f) => _map[f.key] != null)) DataColumn(label: Text(f.value.replaceAll(' *', '')))],
                    rows: [
                      for (final r in _dataRows.take(8))
                        DataRow(cells: [
                          for (final f in _fields.keys.where((k) => _map[k] != null))
                            DataCell(Text(
                              switch (f) {
                                'price' || 'cost' => parseMoney(_cell(r, f)) == null ? '⚠ ${_cell(r, f)}' : money(parseMoney(_cell(r, f))!),
                                _ => _cell(r, f),
                              },
                            )),
                        ]),
                    ],
                  ),
                ),
                if (_map.values.every((v) => v == null)) Text('اختار الأعمدة من فوق', style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            if (_result == null)
              BusyButton(
                label: 'استيراد ${_dataRows.length} صنف',
                icon: Icons.download_done_rounded,
                busy: _busy,
                onPressed: _import,
              ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
          if (_result != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('تم الاستيراد ✅', style: Theme.of(context).textTheme.titleMedium?.bold),
                  const SizedBox(height: 6),
                  Text('أصناف جديدة: ${_result!['created']} • اتحدّث: ${_result!['updated']}'),
                  if ((_result!['errors'] as List).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('صفوف اتجاهلت (${(_result!['errors'] as List).length}):', style: TextStyle(color: scheme.error)),
                    for (final e in (_result!['errors'] as List).take(10)) Text('• $e', style: const TextStyle(fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع للمخزون')),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
