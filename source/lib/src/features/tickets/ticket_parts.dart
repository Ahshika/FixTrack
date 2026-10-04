import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import 'providers.dart';

/// شريط فوق صفحة الجهاز لو ده مرتجع ضمان، بيودّي على الجهاز الأصلي.
class WarrantyBanner extends StatelessWidget {
  const WarrantyBanner({super.key, required this.origin, required this.onOpen});
  final Map<String, dynamic> origin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final until = parseDate(origin['warranty_until']);
    return Material(
      color: brandOrange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.verified_user_rounded, color: brandOrange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'مرتجع ضمان من جهاز #${origin['number']}${until != null ? ' • الضمان لحد ${formatDate(until)}' : ''}',
                style: const TextStyle().semiBold,
              ),
            ),
            const Icon(Icons.chevron_left_rounded),
          ]),
        ),
      ),
    );
  }
}

/// قطع الغيار اللي اتركبت في الجهاز (بتتخصم من المخزون).
class PartsCard extends ConsumerWidget {
  const PartsCard({super.key, required this.detail, required this.user});
  final TicketDetail detail;
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = detail.ticket;
    final canEdit = t.status != TicketStatus.delivered;
    final parts = detail.parts;
    final cost = parts.fold<int>(0, (s, p) => s + (p['costCents'] as int? ?? 0) * (p['qty'] as int));
    return SectionCard(
      title: 'قطع الغيار',
      icon: Icons.memory_rounded,
      trailing: canEdit
          ? TextButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => AddPartDialog(ticket: t, isStaff: user.role != Role.technician)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('قطعة'),
            )
          : null,
      children: [
        if (parts.isEmpty) Text('مفيش قطع اتركبت لسه', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        for (final p in parts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${p['name']} × ${p['qty']}'),
            subtitle: p['costCents'] != null ? Text('التكلفة ${money((p['costCents'] as int) * (p['qty'] as int))}') : null,
            trailing: canEdit
                ? IconButton(
                    tooltip: 'شيل القطعة (ترجع المخزون)',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () async {
                      try {
                        await ref.read(sessionProvider).value!.api!.delete('/api/tickets/${t.id}/parts/${p['id']}');
                        ref.invalidate(ticketDetailProvider(t.id));
                      } catch (e) {
                        if (context.mounted) showMessage(context, errorText(e), error: true);
                      }
                    },
                  )
                : null,
          ),
        if (user.isOwner && parts.isNotEmpty) ...[
          const Divider(),
          Text(
            'تكلفة القطع ${money(cost)} • ربح الصيانة ${money(t.totalCents - cost)}',
            style: const TextStyle(color: Color(0xFF16A34A)).semiBold,
          ),
        ],
      ],
    );
  }
}

class AddPartDialog extends ConsumerStatefulWidget {
  const AddPartDialog({super.key, required this.ticket, required this.isStaff});
  final Ticket ticket;
  final bool isStaff;

  @override
  ConsumerState<AddPartDialog> createState() => _AddPartDialogState();
}

class _AddPartDialogState extends ConsumerState<AddPartDialog> {
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _picked;
  int _qty = 1;
  bool _addToBill = false;
  bool _busy = false;
  String? _error;

  Future<void> _search(String q) async {
    final res = await ref.read(sessionProvider).value!.api!.get('/api/products', query: {'q': q, 'limit': '10'});
    if (!mounted) return;
    setState(() => _results = (res['products'] as List).cast<Map<String, dynamic>>().where((p) => p['serialized'] != true).toList());
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/tickets/${widget.ticket.id}/parts', {
        'productId': _picked!['id'],
        'qty': _qty,
        'addToBill': _addToBill,
      });
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return AlertDialog(
      title: const Text('قطعة غيار للجهاز'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (picked == null) ...[
            TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'دوّر في المخزون (شاشة، بطارية، فلاتة...)', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: ListView(children: [
                for (final p in _results)
                  ListTile(
                    dense: true,
                    title: Text(p['name'] as String),
                    subtitle: Text('متاح ${p['qty']} • ${money(p['priceCents'] as int)}'),
                    onTap: () => setState(() => _picked = p),
                  ),
              ]),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(picked['name'] as String, style: const TextStyle().semiBold),
              subtitle: Text('متاح ${picked['qty']} • سعر البيع ${money(picked['priceCents'] as int)}'),
              trailing: TextButton(onPressed: () => setState(() => _picked = null), child: const Text('تغيير')),
            ),
            Row(children: [
              const Text('الكمية'),
              const Spacer(),
              IconButton(icon: const Icon(Icons.remove_rounded), onPressed: () => setState(() => _qty = (_qty - 1).clamp(1, 100))),
              Text('$_qty', style: const TextStyle().bold),
              IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => setState(() => _qty = (_qty + 1).clamp(1, 100))),
            ]),
            if (widget.isStaff)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _addToBill,
                onChanged: (v) => setState(() => _addToBill = v ?? false),
                title: Text('ضيف سعرها على حساب العميل (+${money((picked['priceCents'] as int) * _qty)})'),
              ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'تركيب', busy: _busy, onPressed: picked == null ? null : _save)),
      ],
    );
  }
}
