import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/ticket_models.dart';
import '../../widgets/common.dart';
import '../../widgets/ticket_widgets.dart';
import '../../core/ticket_status.dart';
import '../../widgets/form_fields.dart';
import '../pos/providers.dart';
import '../tickets/providers.dart';
import '../tickets/tickets_screen.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider(_query));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v.trim()));
              },
              decoration: const InputDecoration(hintText: 'دوّر بالاسم أو رقم التليفون', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: customers.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.people_outline_rounded,
                      message: _query.isEmpty ? 'لسه مفيش عملاء. العملاء بيتسجلوا لوحدهم مع أول جهاز.' : 'مفيش عميل بالاسم أو الرقم ده',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final c = list[i];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Text(c.name.characters.first, style: TextStyle(color: scheme.onPrimaryContainer).bold),
                            ),
                            title: Text(c.name, style: const TextStyle().semiBold),
                            subtitle: Text(
                              '${c.phone}${c.lastVisit != null ? ' • آخر زيارة ${timeAgo(c.lastVisit!)}' : ''}',
                            ),
                            trailing: Text('${c.ticketsCount} ${c.ticketsCount == 1 ? 'جهاز' : 'أجهزة'}'),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(builder: (_) => CustomerDetailScreen(customerId: c.id)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(customerDetailProvider(customerId));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ملف العميل'),
        actions: [
          if (data.hasValue)
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => showDialog<void>(context: context, builder: (_) => _EditCustomerDialog(customer: data.value!.customer)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: data.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
        data: (d) {
          final c = d.customer;
          final total = d.tickets.fold<int>(0, (s, t) => s + t.paidCents);
          final debt = c.balanceCents;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: scheme.primaryContainer,
                          child: Text(c.name.characters.first, style: text.titleLarge?.bold.copyWith(color: scheme.onPrimaryContainer)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.name, style: text.titleLarge?.bold),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: c.phone));
                                showMessage(context, 'اتنسخ الرقم');
                              },
                              child: Text(c.phone, textDirection: TextDirection.ltr, style: TextStyle(color: scheme.onSurfaceVariant)),
                            ),
                            if (c.whatsapp != null && c.whatsapp != c.phone)
                              Text('واتساب: ${c.whatsapp}', style: TextStyle(color: scheme.onSurfaceVariant)),
                          ]),
                        ),
                      ]),
                      if (c.notes != null) ...[const SizedBox(height: 12), Text(c.notes!)],
                      const Divider(height: 28),
                      Row(children: [
                        _Stat(label: 'عدد الأجهزة', value: '${d.tickets.length}'),
                        _Stat(label: 'إجمالي المدفوع', value: money(total)),
                        _Stat(label: 'عليه', value: money(debt), color: debt > 0 ? brandOrange : null),
                      ]),
                    ],
                  ),
                ),
              ),
              if (debt > 0) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => _CollectDialog(customer: c, balanceCents: debt)),
                  icon: const Icon(Icons.payments_rounded),
                  label: Text('تحصيل من العميل (عليه ${money(debt)})'),
                ),
              ],
              _LedgerSection(customerId: c.id),
              const SectionTitle('الأجهزة'),
              for (final t in d.tickets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TicketCard(ticket: t, showCustomer: false, onTap: () => openTicket(context, t.id)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.bold.copyWith(color: color)),
        ]),
      );
}

class _EditCustomerDialog extends ConsumerStatefulWidget {
  const _EditCustomerDialog({required this.customer});
  final Customer customer;

  @override
  ConsumerState<_EditCustomerDialog> createState() => _EditCustomerDialogState();
}

class _EditCustomerDialogState extends ConsumerState<_EditCustomerDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer.name);
  late final _phone = TextEditingController(text: widget.customer.phone);
  late final _whatsapp = TextEditingController(text: widget.customer.whatsapp);
  late final _notes = TextEditingController(text: widget.customer.notes);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _whatsapp, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.patch('/api/customers/${widget.customer.id}', {
        'name': _name.text,
        'phone': _phone.text,
        'whatsapp': _whatsapp.text,
        'notes': _notes.text,
      });
      ref.invalidate(customerDetailProvider(widget.customer.id));
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'تم حفظ بيانات العميل');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل بيانات العميل'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'الاسم'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'لازم تكتب الاسم' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'التليفون')),
            const SizedBox(height: 12),
            TextFormField(controller: _whatsapp, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'الواتساب')),
            const SizedBox(height: 12),
            TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'ملاحظات')),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'حفظ', busy: _busy, onPressed: _save)),
      ],
    );
  }
}

/// كشف حساب العميل: فواتير آجل، وأجهزة صيانة عليها باقي، والمبالغ اللي سددها.
class _LedgerSection extends ConsumerWidget {
  const _LedgerSection({required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(customerLedgerProvider(customerId)).value;
    if (ledger == null || ledger.entries.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('كشف الحساب'),
      Card(
        child: Column(children: [
          for (final e in ledger.entries)
            ListTile(
              dense: true,
              leading: Icon(
                e['type'] == 'payment' ? Icons.south_west_rounded : e['type'] == 'repair' ? Icons.build_rounded : Icons.receipt_long_rounded,
                color: e['type'] == 'payment' ? const Color(0xFF16A34A) : brandOrange,
              ),
              title: Text(e['label'] as String),
              subtitle: Text([if (parseDate(e['createdAt']) != null) formatDateTime(parseDate(e['createdAt'])!), if (e['note'] != null) e['note']].join(' • ')),
              trailing: Text(money(e['amountCents'] as int), style: TextStyle(color: (e['amountCents'] as int) < 0 ? const Color(0xFF16A34A) : scheme.onSurface).bold),
            ),
        ]),
      ),
    ]);
  }
}

class _CollectDialog extends ConsumerStatefulWidget {
  const _CollectDialog({required this.customer, required this.balanceCents});
  final Customer customer;
  final int balanceCents;

  @override
  ConsumerState<_CollectDialog> createState() => _CollectDialogState();
}

class _CollectDialogState extends ConsumerState<_CollectDialog> {
  late final _amount = TextEditingController(text: moneyInput(widget.balanceCents));
  final _note = TextEditingController();
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/customers/${widget.customer.id}/payments', {
        'amountCents': parseMoney(_amount.text),
        'method': _method.name,
        'note': _note.text,
      });
      ref.invalidate(customerDetailProvider(widget.customer.id));
      ref.invalidate(customerLedgerProvider(widget.customer.id));
      if (!mounted) return;
      Navigator.pop(context);
      final left = res['balanceCents'] as int;
      showMessage(context, left > 0 ? 'اتسجل التحصيل. لسه عليه ${money(left)}' : 'اتسجل التحصيل، والحساب خالص ✅');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تحصيل من ${widget.customer.name}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('عليه: ${money(widget.balanceCents)}'),
          const SizedBox(height: 12),
          MoneyField(controller: _amount, label: 'المبلغ', autofocus: true),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.other))
              ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة')),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'تحصيل', busy: _busy, onPressed: _save)),
      ],
    );
  }
}
