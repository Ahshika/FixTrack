import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/shop.dart';
import '../../core/theme.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/suggest_field.dart';
import 'providers.dart';

/// أساس مشترك للـ dialogs اللي بتبعت طلب للسيرفر وتعرض خطأ لو فشل.
mixin _Submitting<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool busy = false;
  String? error;

  Future<void> submit(Future<void> Function() action, {String? success}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      if (success != null) showMessage(context, success);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class EditTicketDialog extends ConsumerStatefulWidget {
  const EditTicketDialog({super.key, required this.ticket, required this.user});
  final Ticket ticket;
  final AppUser user;

  @override
  ConsumerState<EditTicketDialog> createState() => _EditTicketDialogState();
}

class _EditTicketDialogState extends ConsumerState<EditTicketDialog> with _Submitting {
  final _form = GlobalKey<FormState>();
  late final t = widget.ticket;
  late final _brand = TextEditingController(text: t.brand);
  late final _model = TextEditingController(text: t.model);
  late final _color = TextEditingController(text: t.color);
  late final _imei = TextEditingController(text: t.imei);
  late final _problemDesc = TextEditingController(text: t.problemDesc);
  late final _estimated = TextEditingController(text: moneyInput(t.estimatedCents));
  late final _final = TextEditingController(text: t.finalCents == null ? '' : moneyInput(t.finalCents!));
  late Set<String> _problems = {...t.problems};
  late DateTime? _dueAt = t.dueAt;
  late String? _technicianId = t.technicianId;

  bool get _techOnly => widget.user.role == Role.technician;

  @override
  void dispose() {
    for (final c in [_brand, _model, _color, _imei, _problemDesc, _estimated, _final]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = ref.read(sessionProvider).value!.api!;
    final body = _techOnly
        ? {'dueAt': _dueAt?.toIso8601String()}
        : {
            'brand': _brand.text,
            'model': _model.text,
            'color': _color.text,
            'imei': _imei.text,
            'problems': _problems.toList(),
            'problemDesc': _problemDesc.text,
            'estimatedCents': parseMoney(_estimated.text),
            'finalCents': _final.text.trim().isEmpty ? null : parseMoney(_final.text),
            'dueAt': _dueAt?.toIso8601String(),
            'technicianId': _technicianId,
          };
    await submit(() async {
      await api.patch('/api/tickets/${t.id}', body);
      ref.invalidate(ticketDetailProvider(t.id));
    }, success: 'تم حفظ التعديلات');
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffProvider).value ?? const <StaffMember>[];
    return AlertDialog(
      title: Text('تعديل جهاز #${t.number}'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_techOnly) ...[
                  Row(children: [
                    Expanded(
                      child: SuggestField(
                        controller: _brand,
                        label: 'الماركة',
                        textDirection: TextDirection.ltr,
                        options: () => deviceCatalog.keys,
                        validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الماركة' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SuggestField(
                        controller: _model,
                        label: 'الموديل',
                        textDirection: TextDirection.ltr,
                        options: () => deviceCatalog[_brand.text.trim()] ?? deviceCatalog.values.expand((m) => m),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الموديل' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: TextFormField(controller: _color, decoration: const InputDecoration(labelText: 'اللون'))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _imei,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'IMEI / السيريال'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  MultiChips(options: problemOptions, selected: _problems, onChanged: (s) => setState(() => _problems = s)),
                  const SizedBox(height: 12),
                  TextFormField(controller: _problemDesc, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف المشكلة')),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: MoneyField(controller: _estimated, label: 'التكلفة المبدئية')),
                    const SizedBox(width: 12),
                    Expanded(child: MoneyField(controller: _final, label: 'التكلفة النهائية')),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: staff.any((s) => s.id == _technicianId) ? _technicianId : null,
                    decoration: const InputDecoration(labelText: 'الفني المسؤول'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('لسه محددتش')),
                      for (final s in staff.where((s) => s.role != Role.reception))
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (v) => setState(() => _technicianId = v),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('الموعد المتوقع', style: const TextStyle().semiBold),
                const SizedBox(height: 8),
                DuePicker(value: _dueAt, onChanged: (d) => setState(() => _dueAt = d)),
                if (error != null) ...[const SizedBox(height: 12), ErrorBanner(error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'حفظ', busy: busy, onPressed: _save)),
      ],
    );
  }
}

class PaymentDialog extends ConsumerStatefulWidget {
  const PaymentDialog({super.key, required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> with _Submitting {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.ticket.remainingCents > 0 ? moneyInput(widget.ticket.remainingCents) : '');
  final _note = TextEditingController();
  PaymentKind _kind = PaymentKind.payment;
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = ref.read(sessionProvider).value!.api!;
    await submit(() async {
      await api.post('/api/tickets/${widget.ticket.id}/payments', {
        'amountCents': parseMoney(_amount.text),
        'kind': _kind.name,
        'method': _method.name,
        'note': _note.text,
      });
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
    }, success: 'تم تسجيل ${_kind.label} ${money(parseMoney(_amount.text) ?? 0)}');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تسجيل فلوس'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PaymentKind>(
                segments: [for (final k in PaymentKind.values) ButtonSegment(value: k, label: Text(k.label))],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              MoneyField(
                controller: _amount,
                label: 'المبلغ',
                autofocus: true,
                validator: (c) => (c ?? 0) <= 0 ? 'اكتب المبلغ' : null,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in PaymentMethod.values)
                  ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
              ]),
              const SizedBox(height: 12),
              TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
              if (error != null) ...[const SizedBox(height: 12), ErrorBanner(error!)],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'تسجيل', busy: busy, onPressed: _save)),
      ],
    );
  }
}

class DeliverDialog extends ConsumerStatefulWidget {
  const DeliverDialog({super.key, required this.ticket, required this.user});
  final Ticket ticket;
  final AppUser user;

  @override
  ConsumerState<DeliverDialog> createState() => _DeliverDialogState();
}

class _DeliverDialogState extends ConsumerState<DeliverDialog> with _Submitting {
  final _form = GlobalKey<FormState>();
  final _pin = TextEditingController();
  late final _final = TextEditingController(text: moneyInput(widget.ticket.totalCents));
  late final _pay = TextEditingController(text: moneyInput(widget.ticket.remainingCents.clamp(0, 1 << 40)));
  late final _warranty = TextEditingController(text: '${ref.read(shopProvider).value?.repairWarrantyDays ?? 30}');
  PaymentMethod _method = PaymentMethod.cash;
  bool _override = false;
  bool _allowDebt = false;

  @override
  void dispose() {
    _pin.dispose();
    _final.dispose();
    _pay.dispose();
    _warranty.dispose();
    super.dispose();
  }

  int get _finalCents => parseMoney(_final.text) ?? 0;
  int get _payCents => parseMoney(_pay.text) ?? 0;
  int get _remainingAfter => _finalCents - widget.ticket.paidCents - _payCents;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = ref.read(sessionProvider).value!.api!;
    await submit(() async {
      await api.post('/api/tickets/${widget.ticket.id}/deliver', {
        'pin': _pin.text.trim(),
        'override': _override,
        'finalCents': _finalCents,
        'paymentCents': _payCents,
        'paymentMethod': _method.name,
        'allowDebt': _allowDebt,
        'warrantyDays': int.tryParse(latinDigits(_warranty.text)) ?? 0,
      });
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
    }, success: 'تم تسليم الجهاز #${widget.ticket.number} للعميل');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final notReady = !t.status.awaitingPickup;

    return AlertDialog(
      title: Text('تسليم جهاز #${t.number}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${t.deviceName} • ${t.customerName}', style: text.titleSmall?.bold),
                if (notReady) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: brandOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text('الجهاز لسه في مرحلة "${t.status.label}". متأكد إن العميل عايز ياخده؟'),
                  ),
                ],
                if (t.accessories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('ماتنساش ترجّع للعميل: ${t.accessories.join('، ')}', style: TextStyle(color: scheme.primary).semiBold),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pin,
                  enabled: !_override,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  maxLength: 4,
                  decoration: const InputDecoration(labelText: 'كود الاستلام (من وصل العميل)', prefixIcon: Icon(Icons.pin_rounded), counterText: ''),
                  validator: (v) => !_override && latinDigits(v ?? '').trim().length != 4 ? 'اكتب الكود (4 أرقام)' : null,
                  onChanged: (v) {
                    final latin = latinDigits(v);
                    if (latin != v) _pin.value = TextEditingValue(text: latin, selection: TextSelection.collapsed(offset: latin.length));
                  },
                ),
                if (widget.user.isOwner)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _override,
                    onChanged: (v) => setState(() => _override = v ?? false),
                    title: const Text('العميل ضيّع الوصل (تسليم من غير كود)'),
                    subtitle: const Text('اتأكد من شخصية العميل الأول. العملية دي بتتسجل'),
                  ),
                const SizedBox(height: 8),
                if (t.warrantyOf == null) ...[
                  TextFormField(
                    controller: _warranty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'ضمان الصيانة (بالأيام)', prefixIcon: Icon(Icons.verified_user_rounded), helperText: '0 = من غير ضمان'),
                  ),
                  const SizedBox(height: 12),
                ],
                MoneyField(controller: _final, label: 'التكلفة النهائية', onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                Text('مدفوع قبل كده: ${money(t.paidCents)}', style: text.bodySmall),
                const SizedBox(height: 12),
                MoneyField(controller: _pay, label: 'المبلغ اللي هيتدفع دلوقتي', onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                if (_payCents > 0)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final m in PaymentMethod.values)
                      ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
                  ]),
                const SizedBox(height: 12),
                if (_remainingAfter > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _allowDebt,
                    onChanged: (v) => setState(() => _allowDebt = v ?? false),
                    title: Text('هيفضل على العميل ${money(_remainingAfter)} (آجل)'),
                  )
                else if (_remainingAfter < 0)
                  Text(_payCents > 0 ? 'المبلغ أكبر من الباقي بـ ${money(-_remainingAfter)}' : 'المدفوع أكبر من التكلفة بـ ${money(-_remainingAfter)}. سجّل مرتجع بالفرق من كارت "الحساب" الأول', style: TextStyle(color: scheme.error).semiBold)
                else
                  const Text('الحساب خالص ✅'),
                if (error != null) ...[const SizedBox(height: 12), ErrorBanner(error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(
          width: 160,
          child: BusyButton(
            label: 'تأكيد التسليم',
            busy: busy,
            onPressed: (_remainingAfter > 0 && !_allowDebt) || _remainingAfter < 0 ? null : _save,
          ),
        ),
      ],
    );
  }
}

/// الفني أو الاستقبال بيطلب موافقة العميل على تكلفة جديدة.
class ApprovalRequestDialog extends ConsumerStatefulWidget {
  const ApprovalRequestDialog({super.key, required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<ApprovalRequestDialog> createState() => _ApprovalRequestDialogState();
}

class _ApprovalRequestDialogState extends ConsumerState<ApprovalRequestDialog> with _Submitting {
  final _form = GlobalKey<FormState>();
  late final _total = TextEditingController(text: moneyInput(widget.ticket.totalCents));
  final _note = TextEditingController();

  @override
  void dispose() {
    _total.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final api = ref.read(sessionProvider).value!.api!;
    await submit(() async {
      await api.post('/api/tickets/${widget.ticket.id}/approval', {
        'totalCents': parseMoney(_total.text),
        'note': _note.text,
      });
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
    }, success: 'اتبعت طلب الموافقة، والجهاز بقى "في انتظار موافقة العميل"');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('طلب موافقة العميل على تكلفة زيادة'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('التكلفة الحالية: ${money(widget.ticket.totalCents)}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'إيه اللي لقيته؟', hintText: 'مثلاً: الفلاتة كمان محتاجة تتغير'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب السبب عشان العميل يفهم' : null,
              ),
              const SizedBox(height: 12),
              MoneyField(
                controller: _total,
                label: 'التكلفة الجديدة (الإجمالي)',
                validator: (c) => (c ?? 0) <= 0 ? 'اكتب التكلفة الجديدة' : null,
              ),
              const SizedBox(height: 8),
              const Text('العميل هيقدر يوافق أو يرفض من صفحة التتبع، أو تسجل رده بنفسك لو رد في التليفون.',
                  style: TextStyle(fontSize: 12)),
              if (error != null) ...[const SizedBox(height: 12), ErrorBanner(error!)],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 140, child: BusyButton(label: 'اطلب الموافقة', busy: busy, onPressed: _save)),
      ],
    );
  }
}

/// تحديد أو تغيير معاد استلام العميل للجهاز.
class PickupDialog extends ConsumerStatefulWidget {
  const PickupDialog({super.key, required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<PickupDialog> createState() => _PickupDialogState();
}

class _PickupDialogState extends ConsumerState<PickupDialog> with _Submitting {
  late DateTime? _at = widget.ticket.pickupAt;

  Future<void> _save() async {
    final api = ref.read(sessionProvider).value!.api!;
    await submit(() async {
      await api.post('/api/tickets/${widget.ticket.id}/pickup', {'at': _at?.toIso8601String()});
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
    }, success: _at == null ? 'اتلغى معاد الاستلام' : 'معاد الاستلام: ${formatDateTime(_at!)}');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('معاد الاستلام'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('العميل هييجي يستلم إمتى؟'),
            const SizedBox(height: 12),
            DuePicker(value: _at, onChanged: (d) => setState(() => _at = d)),
            if (error != null) ...[const SizedBox(height: 12), ErrorBanner(error!)],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'حفظ', busy: busy, onPressed: _save)),
      ],
    );
  }
}
