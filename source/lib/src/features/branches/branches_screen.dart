import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/realtime.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/ticket_widgets.dart';
import '../tickets/providers.dart';

final _orgProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  refreshOn(ref, 'org');
  return apiOf(ref).get('/api/org');
});

final _transfersProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  refreshOn(ref, 'products');
  return apiOf(ref).get('/api/org/transfers');
});

/// الفروع: ربط فروع المحل، وملخص كل فرع، والمخزون في الفروع التانية، والتحويلات.
class BranchesScreen extends ConsumerWidget {
  const BranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final org = ref.watch(_orgProvider);
    final isOwner = ref.watch(sessionProvider).value!.user!.isOwner;
    return Scaffold(
      appBar: AppBar(title: const Text('الفروع')),
      body: org.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
        data: (o) => o['linked'] == true ? _Linked(org: o, isOwner: isOwner) : _NotLinked(isOwner: isOwner, cloud: o['cloud'] != false),
      ),
    );
  }
}

class _NotLinked extends ConsumerStatefulWidget {
  const _NotLinked({required this.isOwner, required this.cloud});
  final bool isOwner;
  final bool cloud;

  @override
  ConsumerState<_NotLinked> createState() => _NotLinkedState();
}

class _NotLinkedState extends ConsumerState<_NotLinked> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _do(String path, [Map<String, Object?>? body]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.send('POST', path, body: body ?? {}, timeout: const Duration(seconds: 60));
      ref.invalidate(_orgProvider);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOwner) return const EmptyState(icon: Icons.store_mall_directory_outlined, message: 'الفرع ده مش مربوط بفروع تانية. الربط بيعمله صاحب المحل.');
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('لو عندك أكتر من فرع، اربطهم ببعض عشان:\n'
                    '• تشوف مبيعات وأرباح كل فرع من أي مكان\n'
                    '• تعرف الصنف موجود في أنهي فرع\n'
                    '• تحوّل بضاعة من فرع لفرع\n\n'
                    'كل فرع بيفضل شغال لوحده حتى لو النت فصل، والربط بيتحدّث لما النت يرجع.'),
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(title: 'أول فرع', icon: Icons.add_business_rounded, children: [
              const Text('لو ده أول فرع بتربطه، اعمل مجموعة جديدة، وبعدين طلّع كود وادخله في الفروع التانية.'),
              const SizedBox(height: 12),
              BusyButton(label: 'اعمل مجموعة فروع', icon: Icons.hub_rounded, busy: _busy, onPressed: () => _do('/api/org/create')),
            ]),
            const SizedBox(height: 12),
            SectionCard(title: 'فرع تاني', icon: Icons.link_rounded, children: [
              const Text('لو فيه مجموعة معمولة بالفعل: من الفرع الأول دوس "كود ربط فرع جديد"، واكتب الكود هنا.'),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                textDirection: TextDirection.ltr,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'كود الربط (8 حروف)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _busy ? null : () => _do('/api/org/join', {'code': _code.text}), icon: const Icon(Icons.link_rounded), label: const Text('ربط')),
            ]),
            if (!widget.cloud) ...[const SizedBox(height: 12), const ErrorBanner('المزامنة مع النت مقفولة على السيرفر ده، والربط محتاجها.')],
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
          ]),
        ),
      ),
    ]);
  }
}

class _Linked extends ConsumerWidget {
  const _Linked({required this.org, required this.isOwner});
  final Map<String, dynamic> org;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = (org['members'] as List).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
      SectionCard(
        title: '${org['name'] ?? 'الفروع'} • ${members.length} ${members.length == 1 ? 'فرع' : 'فروع'}',
        icon: Icons.hub_rounded,
        trailing: isOwner
            ? TextButton.icon(
                onPressed: () => _invite(context, ref),
                icon: const Icon(Icons.qr_code_rounded, size: 18),
                label: const Text('كود ربط فرع جديد'),
              )
            : null,
        children: [
          for (final m in members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.storefront_rounded, color: m['isMe'] == true ? brandBlue : null),
              title: Text('${m['branchName']}${m['isMe'] == true ? ' (الفرع ده)' : ''}'),
            ),
          if (isOwner)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      content: const Text('فصل الفرع ده عن المجموعة؟ بياناته هنا مش هتتمسح.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('فصل')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  await ref.read(sessionProvider).value!.api!.post('/api/org/leave');
                  ref.invalidate(_orgProvider);
                },
                child: Text('فصل الفرع ده', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (isOwner) ...[const _SummaryCard(), const SizedBox(height: 12)],
      _TransfersCard(members: members),
      const SizedBox(height: 12),
      const _StockLookupCard(),
    ]);
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/org/invite');
      if (!context.mounted) return;
      final code = res['code'] as String;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('كود ربط فرع جديد'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SelectableText(code, style: Theme.of(c).textTheme.displaySmall?.bold.copyWith(letterSpacing: 6), textDirection: TextDirection.ltr),
            const SizedBox(height: 8),
            const Text('في الفرع التاني: الفروع ← "ربط" واكتب الكود ده.\nالكود شغال 24 ساعة.', textAlign: TextAlign.center),
          ]),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: code)), child: const Text('نسخ')),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('تمام')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e), error: true);
    }
  }
}

class _SummaryCard extends ConsumerStatefulWidget {
  const _SummaryCard();

  @override
  ConsumerState<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<_SummaryCard> {
  int _days = 0; // 0 = النهارده
  Future<Map<String, dynamic>>? _future;

  String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _load() {
    final n = DateTime.now();
    _future = ref.read(sessionProvider).value!.api!.send('GET', '/api/org/summary',
        query: {'from': _date(n.subtract(Duration(days: _days))), 'to': _date(n)}, timeout: const Duration(seconds: 60));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: 'ملخص الفروع', icon: Icons.insights_rounded, children: [
      Wrap(spacing: 6, children: [
        for (final e in const {0: 'النهارده', 6: 'آخر 7 أيام', 29: 'آخر 30 يوم'}.entries)
          ChoiceChip(label: Text(e.value), selected: _days == e.key, onSelected: (_) => setState(() {
            _days = e.key;
            _load();
          })),
      ]),
      const SizedBox(height: 8),
      FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorBanner(errorText(snap.error!));
          if (!snap.hasData) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          final branches = (snap.data!['branches'] as List).cast<Map<String, dynamic>>();
          int total(String k) => branches.fold<int>(0, (s, b) => s + (b[k] as int? ?? 0));
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('الفرع')),
                DataColumn(label: Text('المبيعات')),
                DataColumn(label: Text('الصيانة')),
                DataColumn(label: Text('المصروفات')),
                DataColumn(label: Text('صافي الربح')),
                DataColumn(label: Text('آخر تحديث')),
              ],
              rows: [
                for (final b in branches)
                  DataRow(cells: [
                    DataCell(Text('${b['branchName']}${b['isMe'] == true ? ' ★' : ''}')),
                    DataCell(Text(money(b['salesCents'] as int))),
                    DataCell(Text('${money(b['repairsCents'] as int)} (${b['repairsDelivered']})')),
                    DataCell(Text(money(b['expensesCents'] as int))),
                    DataCell(Text(money(b['netProfitCents'] as int), style: const TextStyle().bold)),
                    DataCell(Text(parseDate(b['updatedAt']) == null ? '—' : timeAgo(parseDate(b['updatedAt'])!))),
                  ]),
                DataRow(cells: [
                  DataCell(Text('الإجمالي', style: const TextStyle().bold)),
                  DataCell(Text(money(total('salesCents')), style: const TextStyle().bold)),
                  DataCell(Text(money(total('repairsCents')), style: const TextStyle().bold)),
                  DataCell(Text(money(total('expensesCents')), style: const TextStyle().bold)),
                  DataCell(Text(money(total('netProfitCents')), style: const TextStyle().bold)),
                  const DataCell(Text('')),
                ]),
              ],
            ),
          );
        },
      ),
    ]);
  }
}

class _TransfersCard extends ConsumerWidget {
  const _TransfersCard({required this.members});
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_transfersProvider);
    final others = members.where((m) => m['isMe'] != true).toList();
    return SectionCard(
      title: 'تحويلات البضاعة',
      icon: Icons.swap_horiz_rounded,
      trailing: others.isEmpty
          ? null
          : TextButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => _SendTransferDialog(branches: others)),
              icon: const Icon(Icons.outbox_rounded, size: 18),
              label: const Text('تحويل لفرع'),
            ),
      children: [
        data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (d) {
            final incoming = (d['incoming'] as List).cast<Map<String, dynamic>>();
            final history = (d['history'] as List).cast<Map<String, dynamic>>();
            String itemsText(Map t) => (t['items'] as List).map((i) => '${i['name']} × ${i['qty']}').join('، ');
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final t in incoming)
                Card(
                  color: brandOrange.withValues(alpha: 0.1),
                  child: ListTile(
                    leading: const Icon(Icons.move_to_inbox_rounded, color: brandOrange),
                    title: Text('جاي من ${t['fromName']}'),
                    subtitle: Text(itemsText(t)),
                    trailing: FilledButton(
                      onPressed: () async {
                        try {
                          await ref.read(sessionProvider).value!.api!.send('POST', '/api/org/transfers/${t['id']}/receive', timeout: const Duration(seconds: 60));
                          ref.invalidate(_transfersProvider);
                          if (context.mounted) showMessage(context, 'اتستلم التحويل والبضاعة دخلت المخزون');
                        } catch (e) {
                          if (context.mounted) showMessage(context, errorText(e), error: true);
                        }
                      },
                      child: const Text('استلام'),
                    ),
                  ),
                ),
              if (incoming.isEmpty && history.isEmpty) const Text('مفيش تحويلات لسه'),
              for (final t in history.take(10))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(t['status'] == 'received' ? Icons.check_circle_rounded : Icons.schedule_rounded, color: t['status'] == 'received' ? const Color(0xFF16A34A) : brandOrange),
                  title: Text('${t['fromName']} ← ${t['toName']}'),
                  subtitle: Text('${itemsText(t)}\n${parseDate(t['createdAt']) != null ? formatDateTime(parseDate(t['createdAt'])!) : ''}'),
                  isThreeLine: true,
                ),
            ]);
          },
        ),
      ],
    );
  }
}

class _SendTransferDialog extends ConsumerStatefulWidget {
  const _SendTransferDialog({required this.branches});
  final List<Map<String, dynamic>> branches;

  @override
  ConsumerState<_SendTransferDialog> createState() => _SendTransferDialogState();
}

class _SendTransferDialogState extends ConsumerState<_SendTransferDialog> {
  late String _to = widget.branches.first['uid'] as String;
  final _lines = <Product, int>{};
  List<Product> _results = [];
  Timer? _debounce;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _find(String q) async {
    final res = await ref.read(sessionProvider).value!.api!.get('/api/products', query: {'q': q, 'limit': '8'});
    if (mounted) setState(() => _results = (res['products'] as List).map((j) => Product(j as Map<String, dynamic>)).where((p) => !p.serialized).toList());
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.send('POST', '/api/org/transfers',
          body: {'toUid': _to, 'items': [for (final e in _lines.entries) {'productId': e.key.id, 'qty': e.value}]}, timeout: const Duration(seconds: 60));
      ref.invalidate(_transfersProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'اتبعت التحويل، والفرع التاني هيأكد الاستلام');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تحويل بضاعة لفرع'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: _to,
            decoration: const InputDecoration(labelText: 'لفرع'),
            items: [for (final b in widget.branches) DropdownMenuItem(value: b['uid'] as String, child: Text(b['branchName'] as String))],
            onChanged: (v) => setState(() => _to = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(hintText: 'دوّر على الصنف', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => _find(v));
            },
          ),
          for (final p in _results)
            ListTile(dense: true, title: Text(p.name), subtitle: Text('متاح ${p.qty}'), trailing: const Icon(Icons.add_rounded), onTap: () => setState(() {
              _lines[p] = (_lines[p] ?? 0) + 1;
              _results = [];
            })),
          const Divider(),
          for (final e in _lines.entries)
            Row(children: [
              Expanded(child: Text(e.key.name)),
              IconButton(icon: const Icon(Icons.remove_rounded), onPressed: () => setState(() {
                if (e.value <= 1) {
                  _lines.remove(e.key);
                } else {
                  _lines[e.key] = e.value - 1;
                }
              })),
              Text('${e.value}'),
              IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => setState(() => _lines[e.key] = (e.value + 1).clamp(1, e.key.qty))),
            ]),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'تحويل', busy: _busy, onPressed: _lines.isEmpty ? null : _send)),
      ],
    );
  }
}

class _StockLookupCard extends ConsumerStatefulWidget {
  const _StockLookupCard();

  @override
  ConsumerState<_StockLookupCard> createState() => _StockLookupCardState();
}

class _StockLookupCardState extends ConsumerState<_StockLookupCard> {
  List<Map<String, dynamic>>? _results;
  bool _busy = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) return setState(() => _results = null);
    setState(() => _busy = true);
    try {
      final res = await ref.read(sessionProvider).value!.api!.send('GET', '/api/org/stock', query: {'q': q.trim()}, timeout: const Duration(seconds: 60));
      if (mounted) setState(() => _results = (res['results'] as List).cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: 'الصنف موجود في أنهي فرع؟', icon: Icons.travel_explore_rounded, children: [
      TextField(
        decoration: InputDecoration(
          hintText: 'اسم الصنف أو الباركود',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
        ),
        onChanged: (v) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 500), () => _search(v));
        },
      ),
      if (_results != null && _results!.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('مش موجود في الفروع التانية')),
      for (final r in _results ?? const <Map<String, dynamic>>[])
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storefront_rounded),
          title: Text('${r['name']}'),
          subtitle: Text('${r['branchName']}'),
          trailing: Text('${r['qty']} • ${money(r['priceCents'] as int? ?? 0)}', style: const TextStyle().semiBold),
        ),
      const SizedBox(height: 4),
      Text('المخزون في الفروع التانية بيتحدّث كل ساعة.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}
