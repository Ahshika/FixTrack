import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'providers.dart';

/// الخزنة: كل الفلوس اللي دخلت وخرجت في الوردية، والمصروفات، وتقفيل اليوم.
class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cashCurrentProvider);
    final isOwner = ref.watch(sessionProvider).value!.user!.isOwner;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الخزنة'),
        actions: [
          if (isOwner)
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const _SessionsScreen())),
              icon: const Icon(Icons.history_rounded),
              label: const Text('الأيام اللي فاتت'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: data.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
        data: (d) => _CurrentSession(session: d.session, categories: d.categories, isOwner: isOwner),
      ),
    );
  }
}

class _CurrentSession extends StatelessWidget {
  const _CurrentSession({required this.session, required this.categories, required this.isOwner});
  final CashSession session;
  final List<String> categories;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget stat(String label, int cents, {Color? color}) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: text.bodySmall),
                Text(money(cents), style: text.titleLarge?.bold.copyWith(color: color)),
              ]),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text('الوردية مفتوحة من ${formatDateTime(s.openedAt)}${s.openedBy != null ? ' • ${s.openedBy}' : ''}', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Icon(Icons.point_of_sale_rounded, size: 36, color: scheme.onPrimaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('المفروض يكون في الدرج (كاش)', style: TextStyle(color: scheme.onPrimaryContainer)),
                  Text(money(s.expectedCashCents), style: text.headlineMedium?.bold.copyWith(color: scheme.onPrimaryContainer)),
                  Text('منهم ${money(s.openingCashCents)} كانوا في الدرج أول الوردية', style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          stat('مبيعات', s.salesCents, color: scheme.primary),
          const SizedBox(width: 8),
          stat('صيانة', s.repairsCents, color: const Color(0xFF7C3AED)),
          const SizedBox(width: 8),
          stat('مصروفات', s.expensesCents, color: scheme.error),
        ]),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(spacing: 20, runSpacing: 8, children: [
              for (final e in s.byMethod.entries.where((e) => e.value != 0))
                Text('${e.key.label}: ${money(e.value)}', style: const TextStyle().semiBold),
              if (s.byMethod.values.every((v) => v == 0)) const Text('لسه مفيش حركة في الوردية دي'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.tonalIcon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => _MoveDialog(type: 'expense', categories: categories)),
            icon: const Icon(Icons.remove_circle_outline_rounded),
            label: const Text('مصروف'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const _MoveDialog(type: 'deposit', categories: [])),
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('إيداع في الدرج'),
          ),
          if (isOwner)
            FilledButton.tonalIcon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _MoveDialog(type: 'withdraw', categories: [])),
              icon: const Icon(Icons.outbox_rounded),
              label: const Text('سحب من الدرج'),
            ),
          FilledButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => _CloseDialog(session: s)),
            icon: const Icon(Icons.lock_clock_rounded),
            label: const Text('تقفيل اليوم'),
          ),
        ]),
        const SectionTitle('الحركة'),
        if (s.moves.isEmpty) const Text('مفيش حركة'),
        for (final m in s.moves)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(m.amountCents >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: m.amountCents >= 0 ? const Color(0xFF16A34A) : scheme.error),
            title: Text([cashMoveLabels[m.type] ?? m.type, ?m.category, ?m.note].join(' • ')),
            subtitle: Text('${formatTime(m.createdAt)} • ${m.method.label}${m.userName != null ? ' • ${m.userName}' : ''}'),
            trailing: Text(money(m.amountCents), style: TextStyle(color: m.amountCents >= 0 ? null : scheme.error).bold),
          ),
      ],
    );
  }
}

class _MoveDialog extends ConsumerStatefulWidget {
  const _MoveDialog({required this.type, required this.categories});
  final String type;
  final List<String> categories;

  @override
  ConsumerState<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends ConsumerState<_MoveDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _category;
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/cash/moves', {
        'type': widget.type,
        'amountCents': parseMoney(_amount.text),
        'method': _method.name,
        'category': _category,
        'note': _note.text,
      });
      ref.invalidate(cashCurrentProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = {'expense': 'مصروف', 'deposit': 'إيداع في الدرج', 'withdraw': 'سحب من الدرج'}[widget.type]!;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MoneyField(controller: _amount, label: 'المبلغ', autofocus: true, validator: (c) => (c ?? 0) <= 0 ? 'اكتب المبلغ' : null),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in widget.categories)
                  ChoiceChip(label: Text(c), selected: _category == c, onSelected: (v) => setState(() => _category = v ? c : null)),
              ]),
            ],
            const SizedBox(height: 12),
            TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.other))
                ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
            ]),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'تسجيل', busy: _busy, onPressed: _save)),
      ],
    );
  }
}

class _CloseDialog extends ConsumerStatefulWidget {
  const _CloseDialog({required this.session});
  final CashSession session;

  @override
  ConsumerState<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends ConsumerState<_CloseDialog> {
  final _counted = TextEditingController();
  final _kept = TextEditingController(text: '0');
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;
  CashSession? _closed;

  @override
  void dispose() {
    _counted.dispose();
    _kept.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final counted = parseMoney(_counted.text);
    if (counted == null || _counted.text.trim().isEmpty) {
      setState(() => _error = 'اعدّ الفلوس اللي في الدرج واكتبها');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/cash/close', {
        'countedCashCents': counted,
        'keptCashCents': parseMoney(_kept.text) ?? 0,
        'note': _note.text,
      });
      ref.invalidate(cashCurrentProvider);
      setState(() => _closed = CashSession(res['closed'] as Map<String, dynamic>));
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    if (_closed != null) {
      final diff = _closed!.differenceCents ?? 0;
      return AlertDialog(
        icon: Icon(diff == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded, size: 48, color: diff == 0 ? const Color(0xFF16A34A) : brandOrange),
        title: const Text('اتقفل اليوم'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المتوقع: ${money(_closed!.expectedCashCents)}'),
          Text('اتعد: ${money(_closed!.countedCashCents ?? 0)}'),
          const SizedBox(height: 8),
          Text(
            diff == 0 ? 'الدرج مظبوط ✅' : diff > 0 ? 'زيادة ${money(diff)}' : 'عجز ${money(-diff)}',
            style: text.titleLarge?.bold.copyWith(color: diff == 0 ? const Color(0xFF16A34A) : diff > 0 ? brandOrange : scheme.error),
          ),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تمام'))],
      );
    }
    return AlertDialog(
      title: const Text('تقفيل اليوم'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('المفروض يكون في الدرج: ${money(widget.session.expectedCashCents)}', style: text.titleMedium?.bold),
          const SizedBox(height: 4),
          const Text('اعد الكاش اللي في الدرج فعلاً واكتبه (من غير المحافظ والفيزا).'),
          const SizedBox(height: 12),
          MoneyField(controller: _counted, label: 'الكاش اللي في الدرج', autofocus: true),
          const SizedBox(height: 12),
          MoneyField(controller: _kept, label: 'هيفضل كام في الدرج لبكرة (فكة)؟'),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 140, child: BusyButton(label: 'تقفيل', busy: _busy, onPressed: _save)),
      ],
    );
  }
}

class _SessionsScreen extends ConsumerWidget {
  const _SessionsScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(cashSessionsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الأيام اللي فاتت')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorBanner(errorText(e))),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final s = list[i];
            final diff = s.differenceCents;
            return Card(
              child: ListTile(
                title: Text('${formatDateTime(s.openedAt)}${s.closedAt != null ? ' ← ${formatTime(s.closedAt!)}' : ' (مفتوحة)'}'),
                subtitle: Text('مبيعات ${money(s.salesCents)} • صيانة ${money(s.repairsCents)} • مصروفات ${money(s.expensesCents)}'
                    '${s.closedBy != null ? '\nقفلها: ${s.closedBy}' : ''}'),
                isThreeLine: s.closedBy != null,
                trailing: diff == null
                    ? null
                    : Text(diff == 0 ? 'مظبوط' : diff > 0 ? '+${money(diff)}' : money(diff),
                        style: TextStyle(color: diff == 0 ? const Color(0xFF16A34A) : diff > 0 ? brandOrange : scheme.error).bold),
              ),
            );
          },
        ),
      ),
    );
  }
}
