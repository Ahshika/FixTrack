import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/ticket_widgets.dart';
import '../receipts/print_service.dart';
import 'providers.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  String _query = '';
  bool _dueOnly = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(salesProvider((q: _query, dueOnly: _dueOnly)));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('فواتير البيع')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'رقم الفاتورة، أو اسم العميل، أو اسم صنف', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
            },
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilterChip(label: const Text('آجل بس'), selected: _dueOnly, onSelected: (v) => setState(() => _dueOnly = v)),
          ),
        ),
        Expanded(
          child: sales.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.receipt_long_outlined, message: 'مفيش فواتير')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Text('${s.number}', style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer).bold),
                          ),
                          title: Text('${s.customerName ?? 'عميل نقدي'} • ${s.itemsCount} ${s.itemsCount == 1 ? 'قطعة' : 'قطع'}'),
                          subtitle: Text('${formatDateTime(s.createdAt)}${s.userName != null ? ' • ${s.userName}' : ''}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(money(s.totalCents - s.returnedCents), style: const TextStyle().bold),
                              if (s.dueCents > 0) Text('آجل ${money(s.dueCents)}', style: const TextStyle(fontSize: 12, color: brandOrange)),
                              if (s.returnedCents > 0) Text('فيها مرتجع', style: TextStyle(fontSize: 12, color: scheme.error)),
                            ],
                          ),
                          onTap: () => showDialog<void>(context: context, builder: (_) => SaleDialog(saleId: s.id)),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

/// تفاصيل الفاتورة، وإعادة الطباعة، والمرتجع.
class SaleDialog extends ConsumerWidget {
  const SaleDialog({super.key, required this.saleId});
  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(saleDetailProvider(saleId));
    final isOwner = ref.watch(sessionProvider).value!.user!.isOwner;
    return AlertDialog(
      title: Text(detail.value == null ? 'فاتورة' : 'فاتورة #${detail.value!.sale.number}'),
      content: SizedBox(
        width: 480,
        child: detail.when(
          loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorBanner(errorText(e)),
          data: (d) {
            final s = d.sale;
            final profit = isOwner && d.items.every((i) => i.costCents != null)
                ? d.items.fold<int>(0, (sum, i) => sum + (i.qty - i.returnedQty) * (i.unitPriceCents - i.costCents!)) - s.discountCents
                : null;
            return SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${formatDateTime(s.createdAt)}${s.userName != null ? ' • ${s.userName}' : ''}'),
                if (s.customerName != null) Text('العميل: ${s.customerName}'),
                const Divider(height: 20),
                for (final i in d.items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(i.name),
                    subtitle: Text('${i.qty} × ${money(i.unitPriceCents)}${i.returnedQty > 0 ? ' • رجع ${i.returnedQty}' : ''}'),
                    trailing: Text(money(i.qty * i.unitPriceCents)),
                  ),
                const Divider(height: 20),
                if (s.discountCents > 0) _row('خصم', '- ${money(s.discountCents)}'),
                _row('الإجمالي', money(s.totalCents), bold: true),
                for (final p in d.payments) _row('${cashMoveLabels[p.type] ?? p.type} (${p.method.label})', money(p.amountCents)),
                if (s.returnedCents > 0) _row('قيمة المرتجع', money(s.returnedCents)),
                if (s.dueCents > 0) _row('آجل على العميل', money(s.dueCents), bold: true, color: brandOrange),
                if (profit != null) _row('الربح', money(profit), color: const Color(0xFF16A34A)),
              ]),
            );
          },
        ),
      ),
      actions: [
        if (detail.value != null && detail.value!.items.any((i) => i.returnableQty > 0))
          TextButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => _ReturnDialog(detail: detail.value!)),
            icon: const Icon(Icons.undo_rounded),
            label: const Text('مرتجع'),
          ),
        OutlinedButton.icon(onPressed: () => printSale(context, ref, saleId), icon: const Icon(Icons.print_rounded), label: const Text('طباعة')),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('قفل')),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(color: color).weight(bold ? FontWeight.w700 : FontWeight.w400)),
        ]),
      );
}

class _ReturnDialog extends ConsumerStatefulWidget {
  const _ReturnDialog({required this.detail});
  final SaleDetail detail;

  @override
  ConsumerState<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends ConsumerState<_ReturnDialog> {
  late final Map<String, int> _qty = {for (final i in widget.detail.items) i.id: 0};
  PaymentMethod _method = PaymentMethod.cash;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/sales/${widget.detail.sale.id}/return', {
        'items': [for (final e in _qty.entries) if (e.value > 0) {'saleItemId': e.key, 'qty': e.value}],
        'method': _method.name,
      });
      ref.invalidate(saleDetailProvider(widget.detail.sale.id));
      if (!mounted) return;
      Navigator.pop(context);
      final refund = res['refundCents'] as int;
      showMessage(context, refund > 0 ? 'اتعمل المرتجع. رجّع للعميل ${money(refund)}' : 'اتعمل المرتجع واتخصم من الآجل');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.detail.items.where((i) => i.returnableQty > 0).toList();
    final any = _qty.values.any((q) => q > 0);
    return AlertDialog(
      title: const Text('مرتجع'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('اختار الكمية اللي راجعة من كل صنف. البضاعة هترجع للمخزون.'),
          const SizedBox(height: 8),
          for (final i in items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(i.name),
              subtitle: Text('متاح ترجيع ${i.returnableQty} • ${money(i.unitPriceCents)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.remove_rounded), onPressed: () => setState(() => _qty[i.id] = (_qty[i.id]! - 1).clamp(0, i.returnableQty))),
                Text('${_qty[i.id]}'),
                IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => setState(() => _qty[i.id] = (_qty[i.id]! + 1).clamp(0, i.returnableQty))),
              ]),
            ),
          const SizedBox(height: 8),
          const Text('الفلوس هترجع بـ:'),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.other))
              ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 140, child: BusyButton(label: 'تأكيد المرتجع', busy: _busy, onPressed: any ? _save : null)),
      ],
    );
  }
}
