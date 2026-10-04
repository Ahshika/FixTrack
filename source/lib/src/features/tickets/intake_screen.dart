import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/messages.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pattern_pad.dart';
import '../../widgets/suggest_field.dart';
import '../messages/message_dialog.dart';
import '../receipts/print_service.dart';
import 'providers.dart';

/// استلام جهاز جديد من العميل. لما يتحفظ بيرجع رقم الـ id بتاع الجهاز.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  final _form = GlobalKey<FormState>();

  // العميل
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _whatsapp = TextEditingController();
  bool _whatsappSame = true;
  Customer? _existing;
  bool _lookingUp = false;
  Timer? _lookupDebounce;
  List<Ticket> _warrantyTickets = [];
  String? _warrantyOf;

  // الجهاز
  String _deviceType = 'phone';
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  final _imei = TextEditingController();

  // المشكلة والحالة
  Set<String> _problems = {};
  final _problemDesc = TextEditingController();
  bool? _powersOn;
  Set<String> _condition = {};
  Set<String> _accessories = {};
  final _conditionNotes = TextEditingController();

  // القفل
  LockType _lockType = LockType.none;
  final _lockText = TextEditingController();
  List<int> _pattern = [];

  // الفلوس والمعاد
  final _estimated = TextEditingController();
  final _deposit = TextEditingController();
  PaymentMethod _depositMethod = PaymentMethod.cash;
  DateTime? _dueAt;
  String? _technicianId;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    for (final c in [_phone, _name, _whatsapp, _brand, _model, _color, _imei, _problemDesc, _conditionNotes, _lockText, _estimated, _deposit]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPhoneChanged(String v) {
    _lookupDebounce?.cancel();
    if (_existing != null && normalizePhone(v) != normalizePhone(_existing!.phone)) {
      setState(() => _existing = null);
    }
    if (normalizePhone(v).length < 10) return;
    _lookupDebounce = Timer(const Duration(milliseconds: 400), () => _lookup(v));
  }

  Future<void> _lookup(String phone) async {
    setState(() => _lookingUp = true);
    try {
      final res = await ref.read(sessionProvider).value!.api!.get('/api/customers/lookup', query: {'phone': phone});
      if (!mounted || normalizePhone(_phone.text) != normalizePhone(phone)) return;
      final c = res['customer'] == null ? null : Customer.fromJson(res['customer'] as Map<String, dynamic>);
      unawaited(_checkWarranty(phone: phone));
      setState(() {
        _existing = c;
        if (c != null) {
          _name.text = c.name;
          if (c.whatsapp != null && c.whatsapp != c.phone) {
            _whatsappSame = false;
            _whatsapp.text = c.whatsapp!;
          }
        }
      });
    } catch (_) {
      // البحث عن العميل مش ضروري، لو فشل نكمّل عادي
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  String? get _lockSecret => switch (_lockType) {
        LockType.none => null,
        LockType.pattern => _pattern.length >= 2 ? PatternPad.encode(_pattern) : null,
        _ => _lockText.text.trim().isEmpty ? null : _lockText.text.trim(),
      };

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    if (_problems.isEmpty && _problemDesc.text.trim().isEmpty) {
      setState(() => _error = 'لازم تحدد المشكلة: اختار من القايمة أو اكتب وصف');
      return;
    }
    if (!valid) {
      setState(() => _error = 'فيه بيانات ناقصة أو غلط، راجع الحقول اللي باللون الأحمر');
      return;
    }
    if (_lockType != LockType.none && _lockSecret == null) {
      setState(() => _error = _lockType == LockType.pattern ? 'ارسم الباترن أو اختار "مفيش"' : 'اكتب رمز فتح الشاشة أو اختار "مفيش"');
      return;
    }
    final estimated = parseMoney(_estimated.text)!;
    final deposit = parseMoney(_deposit.text)!;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(sessionProvider).value!.api!;
      final res = await api.post('/api/tickets', {
        'customer': _existing != null
            ? {'id': _existing!.id, 'name': _name.text, 'whatsapp': _whatsappSame ? _phone.text : _whatsapp.text}
            : {'name': _name.text, 'phone': _phone.text, 'whatsapp': _whatsappSame ? _phone.text : _whatsapp.text},
        'deviceType': _deviceType,
        'brand': _brand.text,
        'model': _model.text,
        'color': _color.text,
        'imei': _imei.text,
        'problems': _problems.toList(),
        'problemDesc': _problemDesc.text,
        'powersOn': _powersOn,
        'conditionFlags': _condition.toList(),
        'conditionNotes': _conditionNotes.text,
        'accessories': _accessories.toList(),
        'lockType': _lockType.name,
        'lockSecret': _lockSecret,
        'estimatedCents': estimated,
        'depositCents': deposit,
        'depositMethod': _depositMethod.name,
        'dueAt': _dueAt?.toIso8601String(),
        'technicianId': _technicianId,
        'warrantyOf': ?_warrantyOf,
      });
      final ticket = Ticket(res['ticket'] as Map<String, dynamic>);
      if (!mounted) return;
      await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _IntakeDoneDialog(ticket: ticket));
      if (mounted) Navigator.pop(context, ticket.id);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final left = [_customerSection(), const SizedBox(height: 12), _deviceSection(), const SizedBox(height: 12), _problemSection()];
    final right = [_conditionSection(), const SizedBox(height: 12), _lockSection(), const SizedBox(height: 12), _moneySection()];

    return Scaffold(
      appBar: AppBar(title: const Text('استلام جهاز جديد')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Column(children: left)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(children: right)),
                ],
              )
            else ...[...left, const SizedBox(height: 12), ...right],
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                width: wide ? 320 : double.infinity,
                child: BusyButton(label: 'حفظ واستلام الجهاز', icon: Icons.check_rounded, busy: _busy, onPressed: _submit),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerSection() {
    return SectionCard(
      title: 'العميل',
      icon: Icons.person_rounded,
      children: [
        TextFormField(
          controller: _phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩+\s-]'))],
          decoration: InputDecoration(
            labelText: 'رقم التليفون *',
            prefixIcon: const Icon(Icons.call_rounded),
            suffixIcon: _lookingUp ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
          ),
          onChanged: _onPhoneChanged,
          validator: (v) {
            final d = normalizePhone(v ?? '');
            return d.length < 6 || d.length > 15 ? 'رقم التليفون مش صحيح' : null;
          },
        ),
        for (final w in _warrantyTickets) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: brandOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _warrantyOf == w.id ? brandOrange : Colors.transparent, width: 1.5),
            ),
            child: CheckboxListTile(
              controlAffinity: ListTileControlAffinity.leading,
              value: _warrantyOf == w.id,
              onChanged: (v) => setState(() {
                _warrantyOf = v == true ? w.id : null;
                if (v == true && _estimated.text.trim().isEmpty) _estimated.text = '0';
              }),
              title: Text('${w.deviceName} عليه ضمان من وصل #${w.number} لحد ${formatDate(w.warrantyUntil!)}'),
              subtitle: const Text('علّم هنا لو ده مرتجع ضمان على نفس الإصلاح'),
            ),
          ),
        ],
        if (_existing != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'عميل قديم: ${_existing!.name} • ${_existing!.ticketsCount} ${_existing!.ticketsCount == 1 ? 'زيارة' : 'زيارات'}'
                    '${_existing!.lastVisit != null ? ' • آخر زيارة ${timeAgo(_existing!.lastVisit!)}' : ''}',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'اسم العميل *', prefixIcon: Icon(Icons.badge_rounded)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'لازم تكتب اسم العميل' : null,
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _whatsappSame,
          onChanged: (v) => setState(() => _whatsappSame = v ?? true),
          title: const Text('رقم الواتساب هو نفس الرقم'),
        ),
        if (!_whatsappSame)
          TextFormField(
            controller: _whatsapp,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم الواتساب', prefixIcon: Icon(Icons.chat_rounded)),
          ),
      ],
    );
  }

  Widget _deviceSection() {
    return SectionCard(
      title: 'الجهاز',
      icon: Icons.phone_android_rounded,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: [for (final e in deviceTypes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {_deviceType},
            onSelectionChanged: (s) => setState(() => _deviceType = s.first),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SuggestField(
                controller: _brand,
                label: 'الماركة *',
                icon: Icons.sell_rounded,
                textDirection: TextDirection.ltr,
                options: () => deviceCatalog.keys,
                onSelected: (_) => setState(() {}),
                validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الماركة' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SuggestField(
                controller: _model,
                label: 'الموديل *',
                textDirection: TextDirection.ltr,
                options: () {
                  final brand = deviceCatalog.keys.firstWhere(
                    (b) => b.toLowerCase() == _brand.text.trim().toLowerCase(),
                    orElse: () => '',
                  );
                  return brand.isEmpty ? deviceCatalog.values.expand((m) => m) : deviceCatalog[brand]!;
                },
                validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الموديل' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _color,
                decoration: const InputDecoration(labelText: 'اللون', prefixIcon: Icon(Icons.palette_rounded)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _imei,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'IMEI / السيريال'),
                onChanged: (v) {
                  if (latinDigits(v.trim()).length >= 14) _checkWarranty(imei: latinDigits(v.trim()));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _problemSection() {
    return SectionCard(
      title: 'المشكلة',
      icon: Icons.report_problem_rounded,
      children: [
        MultiChips(options: problemOptions, selected: _problems, onChanged: (s) => setState(() => _problems = s)),
        const SizedBox(height: 12),
        TextFormField(
          controller: _problemDesc,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(labelText: 'وصف المشكلة', hintText: 'مثلاً: الشاشة بتنور بس مفيش صورة، وقع من إيده امبارح'),
        ),
      ],
    );
  }

  Widget _conditionSection() {
    return SectionCard(
      title: 'حالة الجهاز وقت الاستلام',
      icon: Icons.fact_check_rounded,
      children: [
        Text('الجهاز بيفتح؟', style: const TextStyle().semiBold),
        const SizedBox(height: 8),
        SegmentedButton<bool?>(
          segments: const [
            ButtonSegment(value: true, label: Text('بيفتح')),
            ButtonSegment(value: false, label: Text('مبيفتحش')),
            ButtonSegment(value: null, label: Text('مش معروف')),
          ],
          selected: {_powersOn},
          onSelectionChanged: (s) => setState(() => _powersOn = s.first),
        ),
        const SizedBox(height: 14),
        Text('ملاحظات على الشكل', style: const TextStyle().semiBold),
        const SizedBox(height: 8),
        MultiChips(options: conditionOptions, selected: _condition, onChanged: (s) => setState(() => _condition = s)),
        const SizedBox(height: 14),
        Text('الحاجات اللي العميل سابها مع الجهاز', style: const TextStyle().semiBold),
        const SizedBox(height: 8),
        MultiChips(options: accessoryOptions, selected: _accessories, onChanged: (s) => setState(() => _accessories = s)),
        const SizedBox(height: 12),
        TextFormField(
          controller: _conditionNotes,
          decoration: const InputDecoration(labelText: 'ملاحظات تانية'),
        ),
      ],
    );
  }

  Widget _lockSection() {
    return SectionCard(
      title: 'قفل الشاشة',
      icon: Icons.lock_rounded,
      trailing: Tooltip(
        message: 'الرمز بيتخزن متشفر، ومحدش بيشوفه غير الفني المسؤول وصاحب المحل، وبيتمسح لوحده بعد التسليم',
        child: Icon(Icons.shield_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<LockType>(
            segments: [for (final t in LockType.values) ButtonSegment(value: t, label: Text(t.label))],
            selected: {_lockType},
            onSelectionChanged: (s) => setState(() => _lockType = s.first),
          ),
        ),
        if (_lockType == LockType.pattern) ...[
          const SizedBox(height: 12),
          Center(child: PatternPad(initial: _pattern, onChanged: (d) => setState(() => _pattern = d))),
        ] else if (_lockType != LockType.none) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _lockText,
            textDirection: TextDirection.ltr,
            keyboardType: _lockType == LockType.pin ? TextInputType.number : TextInputType.visiblePassword,
            decoration: InputDecoration(labelText: _lockType == LockType.pin ? 'الرقم السري' : 'الباسورد', prefixIcon: const Icon(Icons.key_rounded)),
          ),
        ],
      ],
    );
  }

  Widget _moneySection() {
    final staff = ref.watch(staffProvider).value ?? const <StaffMember>[];
    final me = ref.watch(sessionProvider).value!.user!;
    return SectionCard(
      title: 'التكلفة والموعد',
      icon: Icons.receipt_long_rounded,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: MoneyField(controller: _estimated, label: 'التكلفة المبدئية', onChanged: (_) => setState(() {}))),
            const SizedBox(width: 12),
            Expanded(
              child: MoneyField(
                controller: _deposit,
                label: 'العربون',
                onChanged: (_) => setState(() {}),
                validator: (cents) {
                  final est = parseMoney(_estimated.text) ?? 0;
                  return est > 0 && (cents ?? 0) > est ? 'العربون أكبر من التكلفة' : null;
                },
              ),
            ),
          ],
        ),
        if ((parseMoney(_deposit.text) ?? 0) > 0) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(label: Text(m.label), selected: _depositMethod == m, onSelected: (_) => setState(() => _depositMethod = m)),
            ],
          ),
        ],
        if ((parseMoney(_estimated.text) ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            'الباقي على العميل: ${money((parseMoney(_estimated.text) ?? 0) - (parseMoney(_deposit.text) ?? 0))}',
            style: TextStyle(color: Theme.of(context).colorScheme.primary).semiBold,
          ),
        ],
        const SizedBox(height: 16),
        Text('الموعد المتوقع للانتهاء', style: const TextStyle().semiBold),
        const SizedBox(height: 8),
        DuePicker(value: _dueAt, onChanged: (d) => setState(() => _dueAt = d)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: _technicianId,
          decoration: const InputDecoration(labelText: 'الفني المسؤول', prefixIcon: Icon(Icons.engineering_rounded)),
          items: [
            const DropdownMenuItem(value: null, child: Text('لسه محددتش')),
            for (final s in staff.where((s) => s.role != Role.reception))
              DropdownMenuItem(value: s.id, child: Text('${s.name}${s.id == me.id ? ' (إنت)' : ''}')),
          ],
          onChanged: (v) => setState(() => _technicianId = v),
        ),
      ],
    );
  }
}

class _IntakeDoneDialog extends ConsumerWidget {
  const _IntakeDoneDialog({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 56),
      title: const Text('تم استلام الجهاز'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${ticket.deviceName} • ${ticket.customerName}', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _BigValue(label: 'رقم الوصل', value: '#${ticket.number}', color: scheme.primary)),
              const SizedBox(width: 12),
              Expanded(child: _BigValue(label: 'كود الاستلام', value: ticket.pickupPin ?? '', color: brandOrange)),
            ],
          ),
          const SizedBox(height: 12),
          Text('قول للعميل على كود الاستلام، أو اطبعله الوصل. من غيره مش هيقدر يستلم الجهاز.',
              textAlign: TextAlign.center, style: text.bodySmall),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => showMessageDialog(context, ticket.id, MessageEvent.received),
          icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
          label: const Text('واتساب'),
        ),
        OutlinedButton.icon(
          onPressed: () => printTicket(context, ref, ticket.id, PrintKind.receipt),
          icon: const Icon(Icons.print_rounded),
          label: const Text('طباعة الوصل'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
      ],
    );
  }
}

class _BigValue extends StatelessWidget {
  const _BigValue({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.headlineMedium?.bold.copyWith(color: color, letterSpacing: 2)),
      ]),
    );
  }
}

extension on _IntakeScreenState {
  /// لو العميل أو الجهاز عليه ضمان من إصلاح قبل كده، بنعرضه عشان يتسجل كمرتجع ضمان.
  Future<void> _checkWarranty({String? phone, String? imei}) async {
    try {
      final res = await ref.read(sessionProvider).value!.api!.get('/api/warranty-check', query: {'phone': ?phone, 'imei': ?imei});
      final list = (res['tickets'] as List).map((j) => Ticket(j as Map<String, dynamic>)).toList();
      if (!mounted) return;
      // ignore: invalid_use_of_protected_member
      setState(() {
        final ids = {for (final t in _warrantyTickets) t.id};
        _warrantyTickets = [..._warrantyTickets, ...list.where((t) => !ids.contains(t.id))];
      });
    } catch (_) {}
  }
}
