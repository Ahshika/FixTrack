import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/diagnostics.dart';
import '../../core/format.dart';
import '../../core/session.dart';
import '../../core/shop.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

const paperLabels = {
  '80mm': 'طابعة حرارية 80 مم',
  '58mm': 'طابعة حرارية 58 مم (صغيرة)',
  'a5': 'ورق A5',
  'a4': 'ورق A4',
};

/// بيانات المحل اللي بتظهر في الوصل والرسائل (لصاحب المحل بس).
class ShopSettingsScreen extends ConsumerWidget {
  const ShopSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات المحل والوصل')),
      body: shop.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
        data: (s) => _ShopForm(shop: s),
      ),
    );
  }
}

class _ShopForm extends ConsumerStatefulWidget {
  const _ShopForm({required this.shop});
  final ShopProfile shop;

  @override
  ConsumerState<_ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends ConsumerState<_ShopForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.shop.name);
  late final _phone = TextEditingController(text: widget.shop.phone);
  late final _address = TextEditingController(text: widget.shop.address);
  late final _branch = TextEditingController(text: widget.shop.branchName);
  late final _terms = TextEditingController(text: widget.shop.receiptTerms);
  late String _paper = widget.shop.receiptPaper;
  late final Set<int> _days = {...((widget.shop.pickupHours['days'] as List?) ?? const []).cast<int>()};
  late String _from = widget.shop.pickupHours['from'] as String? ?? '12:00';
  late String _to = widget.shop.pickupHours['to'] as String? ?? '22:00';
  late int _slot = widget.shop.pickupHours['slotMinutes'] as int? ?? 30;
  late bool _cashierDiscount = widget.shop.cashierCanDiscount;
  late bool _negativeStock = widget.shop.allowNegativeStock;
  late final _warrantyDays = TextEditingController(text: '${widget.shop.repairWarrantyDays}');
  bool _busy = false;
  bool _logoBusy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _branch, _terms, _warrantyDays]) {
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
      await ref.read(sessionProvider).value!.api!.patch('/api/shop', {
        'name': _name.text,
        'phone': _phone.text,
        'address': _address.text,
        'branchName': _branch.text,
        'receiptTerms': _terms.text,
        'receiptPaper': _paper,
        'pickupHours': {'days': _days.toList(), 'from': _from, 'to': _to, 'slotMinutes': _slot},
        'cashierCanDiscount': _cashierDiscount,
        'allowNegativeStock': _negativeStock,
        'repairWarrantyDays': int.tryParse(latinDigits(_warrantyDays.text)) ?? 30,
      });
      ref.invalidate(shopProvider);
      if (mounted) showMessage(context, 'تم حفظ بيانات المحل');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickLogo() async {
    // بنفتح على فولدر الصور اللي على الجهاز، مش آخر فولدر (لو كان موبايل متوصل أو فولدر شبكة، ويندوز ممكن يعلّق فيه)
    final pictures = '${Platform.environment['USERPROFILE'] ?? ''}\\Pictures';
    FreezeWatchdog.action('نافذة اختيار اللوجو من ويندوز');
    DiagLog.app?.write('INFO', 'فتح نافذة اختيار اللوجو');
    final file = await openFile(
      initialDirectory: Platform.isWindows && Directory(pictures).existsSync() ? pictures : null,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'صور', extensions: ['png', 'jpg', 'jpeg', 'webp'], mimeTypes: ['image/*']),
      ],
    );
    DiagLog.app?.write('INFO', file == null ? 'نافذة اختيار اللوجو اتقفلت من غير اختيار' : 'اتختار لوجو');
    if (file == null) return;
    setState(() => _logoBusy = true);
    try {
      final raw = await file.readAsBytes();
      // بنصغّر اللوجو (في Isolate لوحده) عشان الوصل يطبع بسرعة والصورة ماتتقلش على الشبكة
      final png = await Isolate.run(() {
        final decoded = img.decodeImage(raw);
        if (decoded == null) return null;
        final resized = decoded.width > 400 || decoded.height > 400
            ? img.copyResize(decoded, width: decoded.width >= decoded.height ? 400 : null, height: decoded.height > decoded.width ? 400 : null)
            : decoded;
        return img.encodePng(resized);
      });
      if (png == null) throw Exception('الملف ده مش صورة');
      await ref.read(sessionProvider).value!.api!.put('/api/shop/logo', {'png': base64.encode(png)});
      ref.invalidate(shopProvider);
      if (mounted) showMessage(context, 'اتحفظ اللوجو');
    } catch (e) {
      if (mounted) showMessage(context, e is Exception ? e.toString().replaceFirst('Exception: ', '') : errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _logoBusy = false);
    }
  }

  Future<void> _removeLogo() async {
    await ref.read(sessionProvider).value!.api!.delete('/api/shop/logo');
    ref.invalidate(shopProvider);
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.shop.logo;
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    title: 'اللوجو',
                    icon: Icons.image_rounded,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: logo == null
                                ? Icon(Icons.add_photo_alternate_rounded, size: 36, color: scheme.outline)
                                : Image.memory(logo, fit: BoxFit.contain),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('بيظهر فوق في الوصل. الأحسن صورة بخلفية بيضا أو شفافة.'),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _logoBusy ? null : _pickLogo,
                                    icon: _logoBusy
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.upload_rounded),
                                    label: Text(logo == null ? 'اختار صورة' : 'تغيير'),
                                  ),
                                  if (logo != null) TextButton(onPressed: _removeLogo, child: const Text('مسح')),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'بيانات المحل',
                    icon: Icons.storefront_rounded,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'اسم المحل'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'لازم تكتب اسم المحل' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _branch,
                        decoration: const InputDecoration(labelText: 'اسم الفرع'),
                        validator: (v) => (v ?? '').trim().isEmpty ? 'لازم تكتب اسم الفرع' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'تليفون المحل')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'العنوان')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'الوصل',
                    icon: Icons.receipt_long_rounded,
                    children: [
                      Text('مقاس الورق', style: const TextStyle().semiBold),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final e in paperLabels.entries)
                          ChoiceChip(label: Text(e.value), selected: _paper == e.key, onSelected: (_) => setState(() => _paper = e.key)),
                      ]),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _terms,
                        minLines: 3,
                        maxLines: 8,
                        decoration: const InputDecoration(labelText: 'الشروط اللي بتتطبع تحت الوصل', alignLabelWithHint: true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _pickupSection(),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'البيع',
                    icon: Icons.point_of_sale_rounded,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('الكاشير يقدر يعمل خصم ويغيّر السعر'),
                        subtitle: const Text('لو اتقفلت، الخصم لصاحب المحل بس'),
                        value: _cashierDiscount,
                        onChanged: (v) => setState(() => _cashierDiscount = v),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('السماح بالبيع لو الكمية في البرنامج خلصت'),
                        subtitle: const Text('مفيد لو فيه بضاعة لسه ما اتسجلتش'),
                        value: _negativeStock,
                        onChanged: (v) => setState(() => _negativeStock = v),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _warrantyDays,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'ضمان الصيانة الافتراضي (بالأيام)', prefixIcon: Icon(Icons.verified_user_rounded)),
                      ),
                    ],
                  ),
                  if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
                  const SizedBox(height: 16),
                  BusyButton(label: 'حفظ', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on _ShopFormState {
  Widget _pickupSection() {
    const dayNames = ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت'];
    String label(String hhmm) {
      final p = hhmm.split(':').map(int.parse).toList();
      return formatTime(DateTime(2000, 1, 1, p[0], p[1]));
    }

    Future<void> pick(bool isFrom) async {
      final cur = (isFrom ? _from : _to).split(':').map(int.parse).toList();
      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: cur[0], minute: cur[1]));
      if (t == null) return;
      final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      // ignore: invalid_use_of_protected_member
      setState(() => isFrom ? _from = v : _to = v);
    }

    return SectionCard(
      title: 'مواعيد استلام العملاء',
      icon: Icons.event_available_rounded,
      children: [
        const Text('العميل بيحجز معاد يستلم فيه جهازه من صفحة التتبع، في الأيام والساعات دي بس.'),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var d = 0; d < 7; d++)
            FilterChip(
              label: Text(dayNames[d]),
              selected: _days.contains(d),
              // ignore: invalid_use_of_protected_member
              onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => pick(true), icon: const Icon(Icons.schedule_rounded), label: Text('من ${label(_from)}'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () => pick(false), icon: const Icon(Icons.schedule_rounded), label: Text('لـ ${label(_to)}'))),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 15, label: Text('كل ربع ساعة')),
            ButtonSegment(value: 30, label: Text('كل نص ساعة')),
            ButtonSegment(value: 60, label: Text('كل ساعة')),
          ],
          selected: {_slot},
          // ignore: invalid_use_of_protected_member
          onSelectionChanged: (s) => setState(() => _slot = s.first),
        ),
      ],
    );
  }
}
