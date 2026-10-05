import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart' hide XFile;

import '../../core/diagnostics.dart';
import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/ticket_status.dart';
import '../../widgets/barcode_scan.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/ticket_widgets.dart';
import '../pos/providers.dart';
import '../receipts/print_service.dart';

/// الموبايلات الجديدة والمستعملة اللي في المحل، كل جهاز بالـ IMEI بتاعه.
class PhonesScreen extends ConsumerStatefulWidget {
  const PhonesScreen({super.key});

  @override
  ConsumerState<PhonesScreen> createState() => _PhonesScreenState();
}

class _PhonesScreenState extends ConsumerState<PhonesScreen> {
  String _status = 'in_stock';
  String? _condition;
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider((status: _status, condition: _condition, q: _query, productId: null)));
    final isOwner = ref.watch(sessionProvider).value!.user!.isOwner;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموبايلات'),
        actions: [
          TextButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const ImeiCheckDialog()),
            icon: const Icon(Icons.manage_search_rounded),
            label: const Text('فحص IMEI'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const BuyUsedScreen())),
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: const Text('شرا موبايل مستعمل'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'دوّر بالـ IMEI أو الموديل', prefixIcon: Icon(Icons.search_rounded)),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
            },
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final s in const {'in_stock': 'في المحل', 'sold': 'اتباع', 'all': 'الكل'}.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(s.value), selected: _status == s.key, onSelected: (_) => setState(() => _status = s.key)),
              ),
            const SizedBox(width: 12),
            for (final c in const {null: 'جديد ومستعمل', 'new': 'جديد', 'used': 'مستعمل'}.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(c.value), selected: _condition == c.key, onSelected: (_) => setState(() => _condition = c.key)),
              ),
          ]),
        ),
        Expanded(
          child: units.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
            data: (list) => list.isEmpty
                ? const EmptyState(
                    icon: Icons.phone_iphone_rounded,
                    message: 'مفيش موبايلات هنا.\nالموبايلات الجديدة بتدخل من "المشتريات"، والمستعملة من زرار "شرا موبايل مستعمل".',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) => _UnitTile(unit: list[i], showCost: isOwner),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.showCost});
  final PhoneUnit unit;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final u = unit;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (u.isUsed ? brandOrange : scheme.primary).withValues(alpha: 0.12),
          child: Icon(Icons.phone_iphone_rounded, color: u.isUsed ? brandOrange : scheme.primary),
        ),
        title: Text(u.productName, style: const TextStyle().semiBold),
        subtitle: Text(['IMEI ${u.imei}', if (u.details.isNotEmpty) u.details, if (showCost && u.costCents != null) 'شرا ${money(u.costCents!)}'].join(' • ')),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(u.priceCents), style: TextStyle(color: scheme.primary).bold),
          if (u.status == 'sold') Text('اتباع ${u.soldAt != null ? formatDay(u.soldAt!) : ''}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ]),
        onTap: () => showDialog<void>(context: context, builder: (_) => ImeiCheckDialog(initialImei: u.imei)),
      ),
    );
  }
}

/// في الكاشير: اختيار الجهاز اللي هيتباع من موديل معين (بالمسح أو من القايمة).
class UnitPickerDialog extends ConsumerStatefulWidget {
  const UnitPickerDialog({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<UnitPickerDialog> createState() => _UnitPickerDialogState();
}

class _UnitPickerDialogState extends ConsumerState<UnitPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final units = ref.watch(unitsProvider((status: 'in_stock', condition: null, q: _q, productId: widget.product.id)));
    return AlertDialog(
      title: Text('اختار الجهاز: ${widget.product.name}'),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'امسح أو اكتب الـ IMEI',
              prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
              suffixIcon: cameraScanSupported
                  ? IconButton(
                      icon: const Icon(Icons.photo_camera_rounded),
                      onPressed: () async {
                        final c = await scanBarcode(context);
                        if (c != null) setState(() => _q = latinDigits(c));
                      },
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _q = latinDigits(v.trim())),
            onSubmitted: (v) {
              final list = units.value ?? const [];
              if (list.length == 1) Navigator.pop(context, list.first);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: units.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorBanner(errorText(e)),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('مفيش أجهزة من الموديل ده في المحل'))
                  : ListView(children: [
                      for (final u in list)
                        ListTile(
                          title: Text('IMEI ${u.imei}', textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                          subtitle: Text(u.details.isEmpty ? 'جديد' : u.details),
                          trailing: Text(money(u.priceCents), style: const TextStyle().bold),
                          onTap: () => Navigator.pop(context, u),
                        ),
                    ]),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء'))],
    );
  }
}

/// كل حاجة البرنامج يعرفها عن IMEI معين. مهم قبل شرا موبايل مستعمل.
class ImeiCheckDialog extends ConsumerStatefulWidget {
  const ImeiCheckDialog({super.key, this.initialImei});
  final String? initialImei;

  @override
  ConsumerState<ImeiCheckDialog> createState() => _ImeiCheckDialogState();
}

class _ImeiCheckDialogState extends ConsumerState<ImeiCheckDialog> {
  late final _imei = TextEditingController(text: widget.initialImei);
  Map<String, dynamic>? _result;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialImei != null) _check();
  }

  @override
  void dispose() {
    _imei.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final v = latinDigits(_imei.text.trim());
    if (v.length < 8) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(sessionProvider).value!.api!.get('/api/imei/$v');
      setState(() => _result = r);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _result;
    final units = (r?['units'] as List? ?? const []).map((j) => PhoneUnit(j as Map<String, dynamic>)).toList();
    final tickets = (r?['tickets'] as List? ?? const []).cast<Map<String, dynamic>>();
    return AlertDialog(
      title: const Text('فحص IMEI'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _imei,
              autofocus: widget.initialImei == null,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'اكتب الـ IMEI (اطلب *#06# على الموبايل)',
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (cameraScanSupported)
                    IconButton(
                      icon: const Icon(Icons.photo_camera_rounded),
                      onPressed: () async {
                        final c = await scanBarcode(context);
                        if (c != null) {
                          _imei.text = c;
                          await _check();
                        }
                      },
                    ),
                  IconButton(icon: const Icon(Icons.search_rounded), onPressed: _check),
                ]),
              ),
              onSubmitted: (_) => _check(),
            ),
            if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
            if (r != null) ...[
              const SizedBox(height: 12),
              if (r['validImei'] != true)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: brandOrange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: const Text('⚠ الرقم ده مش IMEI صحيح (المفروض 15 رقم وآخر رقم بيطابق). اتأكد إنك كتبته صح.'),
                ),
              if (units.isEmpty && tickets.isEmpty) ...[
                const SizedBox(height: 8),
                const Text('الجهاز ده ما عداش على المحل قبل كده.'),
              ],
              for (final u in units)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${u.productName} • ${u.status == 'sold' ? 'اتباع' : 'في المحل'}', style: const TextStyle().bold),
                      if (u.details.isNotEmpty) Text(u.details),
                      Text(u.source == 'customer'
                          ? 'اتشرا من: ${u.sellerName ?? ''} • ${u.sellerPhone ?? ''}'
                          : u.supplierName != null
                              ? 'اتشرا من المورد: ${u.supplierName}'
                              : 'اتضاف للمخزون'),
                      if (u.sellerNationalId != null) Text('الرقم القومي: ${u.sellerNationalId}', textDirection: TextDirection.rtl),
                      if (u.createdAt != null) Text('دخل المحل: ${formatDateTime(u.createdAt!)}'),
                      if (u.soldAt != null) Text('اتباع: ${formatDateTime(u.soldAt!)}${u.soldToName != null ? ' لـ ${u.soldToName}' : ''}'),
                      if (u.sellerIdPhoto != null)
                        TextButton.icon(
                          onPressed: () => showDialog<void>(context: context, builder: (_) => _PhotoDialog(fileId: u.sellerIdPhoto!)),
                          icon: const Icon(Icons.badge_rounded),
                          label: const Text('صورة البطاقة'),
                        ),
                      if (u.source == 'customer')
                        TextButton.icon(
                          onPressed: () => printUsedPurchase(context, ref, u),
                          icon: const Icon(Icons.print_rounded),
                          label: const Text('طباعة إيصال الشرا'),
                        ),
                    ]),
                  ),
                ),
              for (final t in tickets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.build_rounded, color: scheme.primary),
                  title: Text('صيانة #${t['number']} • ${t['device']}'),
                  subtitle: Text('${t['customerName']}${t['customerPhone'] != null ? ' • ${t['customerPhone']}' : ''} • ${formatDate(parseDate(t['createdAt'])!)}'),
                  trailing: StatusChip(TicketStatus.parse(t['status'] as String?), dense: true),
                ),
            ],
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('قفل'))],
    );
  }
}

class _PhotoDialog extends ConsumerWidget {
  const _PhotoDialog({required this.fileId});
  final String fileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(sessionProvider).value!.api!;
    FreezeWatchdog.action('عرض صورة كبيرة');
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          child: Image.network(
            '${api.baseUrl}/api/files/$fileId',
            headers: {'authorization': 'Bearer ${api.token}'},
            errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(40), child: Text('مش قادر أفتح الصورة')),
          ),
        ),
      ),
    );
  }
}

/// تصوير صورة (كاميرا على الموبايل، أو اختيار ملف على الكمبيوتر) وتصغيرها ورفعها للسيرفر.
Future<String?> captureAndUploadPhoto(BuildContext context, WidgetRef ref, String kind) async {
  final XFile? file;
  if (Platform.isAndroid || Platform.isIOS) {
    file = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80);
  } else {
    // بنفتح على فولدر الصور اللي على الجهاز، مش آخر فولدر (لو كان موبايل متوصل أو فولدر شبكة، ويندوز ممكن يعلّق فيه)
    final pictures = '${Platform.environment['USERPROFILE'] ?? ''}\\Pictures';
    FreezeWatchdog.action('نافذة اختيار صورة من ويندوز');
    DiagLog.app?.write('INFO', 'فتح نافذة اختيار صورة');
    file = await openFile(
      initialDirectory: Directory(pictures).existsSync() ? pictures : null,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'صور', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ],
    );
    DiagLog.app?.write('INFO', file == null ? 'نافذة اختيار الصورة اتقفلت من غير اختيار' : 'اتختارت صورة ${await file.length() ~/ 1024} KB');
  }
  if (file == null) return null;
  final raw = await file.readAsBytes();
  // التصغير في Isolate لوحده: صورة موبايل 12 ميجابكسل بتاخد ثواني، والشاشة ماينفعش تقف
  final bytes = await Isolate.run(() {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    final resized = decoded.width > 1400 ? img.copyResize(decoded, width: 1400) : decoded;
    return img.encodeJpg(resized, quality: 75);
  });
  if (bytes == null) throw Exception('الملف ده مش صورة');
  final res = await ref.read(sessionProvider).value!.api!.post('/api/files', {'data': base64.encode(bytes), 'kind': kind});
  return res['id'] as String;
}

/// شرا موبايل مستعمل من زبون: الجهاز والـ IMEI، وبيانات البائع وصورة بطاقته، والسعر.
class BuyUsedScreen extends ConsumerStatefulWidget {
  const BuyUsedScreen({super.key});

  @override
  ConsumerState<BuyUsedScreen> createState() => _BuyUsedScreenState();
}

class _BuyUsedScreenState extends ConsumerState<BuyUsedScreen> {
  final _form = GlobalKey<FormState>();
  final _model = TextEditingController();
  final _imei = TextEditingController();
  final _color = TextEditingController();
  final _storage = TextEditingController();
  final _notes = TextEditingController();
  final _sellerName = TextEditingController();
  final _sellerPhone = TextEditingController();
  final _nationalId = TextEditingController();
  final _cost = TextEditingController();
  final _price = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  String? _photoId;
  Map<String, dynamic>? _imeiInfo;
  bool _busy = false;
  bool _photoBusy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_model, _imei, _color, _storage, _notes, _sellerName, _sellerPhone, _nationalId, _cost, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkImei() async {
    final v = latinDigits(_imei.text.trim());
    if (v.length < 8) return;
    try {
      final r = await ref.read(sessionProvider).value!.api!.get('/api/imei/$v');
      setState(() => _imeiInfo = r);
    } catch (_) {}
  }

  Future<void> _photo() async {
    setState(() => _photoBusy = true);
    try {
      final id = await captureAndUploadPhoto(context, ref, 'national_id');
      if (id != null) setState(() => _photoId = id);
    } catch (e) {
      if (mounted) showMessage(context, e is Exception ? e.toString().replaceFirst('Exception: ', '') : errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_photoId == null) {
      setState(() => _error = 'صوّر بطاقة البائع الأول (للحماية من الأجهزة المسروقة)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/units/buy-used', {
        'model': _model.text,
        'imei': _imei.text,
        'color': _color.text,
        'storage': _storage.text,
        'notes': _notes.text,
        'sellerName': _sellerName.text,
        'sellerPhone': _sellerPhone.text,
        'sellerNationalId': latinDigits(_nationalId.text.trim()),
        'idPhotoId': _photoId,
        'costCents': parseMoney(_cost.text),
        'priceCents': parseMoney(_price.text),
        'method': _method.name,
      });
      final unit = PhoneUnit(res['unit'] as Map<String, dynamic>);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 48),
          title: const Text('اتسجل الجهاز'),
          content: Text('${unit.productName}\nIMEI ${unit.imei}\nادفع للبائع ${money(unit.costCents ?? 0)} من الخزنة.\nاطبع الإيصال وخلّي البائع يمضي عليه.'),
          actions: [
            OutlinedButton.icon(onPressed: () => printUsedPurchase(context, ref, unit), icon: const Icon(Icons.print_rounded), label: const Text('طباعة الإيصال')),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _imeiInfo;
    final history = (info?['units'] as List? ?? const []).length + (info?['tickets'] as List? ?? const []).length;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final device = SectionCard(title: 'الجهاز', icon: Icons.phone_iphone_rounded, children: [
      TextFormField(
        controller: _model,
        decoration: const InputDecoration(labelText: 'الموديل * (مثلاً iPhone 12 128GB)'),
        validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الموديل' : null,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _imei,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: 'IMEI * (اطلب *#06#)',
          suffixIcon: cameraScanSupported
              ? IconButton(
                  icon: const Icon(Icons.photo_camera_rounded),
                  onPressed: () async {
                    final c = await scanBarcode(context);
                    if (c != null) {
                      _imei.text = c;
                      await _checkImei();
                    }
                  },
                )
              : null,
        ),
        onChanged: (v) {
          if (latinDigits(v.trim()).length == 15) _checkImei();
        },
        onFieldSubmitted: (_) => _checkImei(),
        validator: (v) => latinDigits(v ?? '').trim().length < 8 ? 'اكتب الـ IMEI' : null,
      ),
      if (info != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (history > 0 || info['validImei'] != true ? brandOrange : const Color(0xFF16A34A)).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Text(info['validImei'] != true
                  ? '⚠ الـ IMEI ده مش صحيح، راجعه'
                  : history > 0
                      ? '⚠ الجهاز ده عدّى على المحل قبل كده ($history مرة)'
                      : '✓ الجهاز ما عداش على المحل قبل كده'),
            ),
            if (history > 0)
              TextButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => ImeiCheckDialog(initialImei: latinDigits(_imei.text.trim()))),
                child: const Text('التفاصيل'),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextFormField(controller: _color, decoration: const InputDecoration(labelText: 'اللون'))),
        const SizedBox(width: 12),
        Expanded(child: TextFormField(controller: _storage, decoration: const InputDecoration(labelText: 'المساحة'))),
      ]),
      const SizedBox(height: 12),
      TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'حالة الجهاز (البطارية، الخدوش، اتفتح قبل كده...)')),
    ]);
    final seller = SectionCard(title: 'البائع', icon: Icons.badge_rounded, children: [
      TextFormField(controller: _sellerName, decoration: const InputDecoration(labelText: 'الاسم (زي البطاقة) *'), validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب الاسم' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _sellerPhone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'التليفون *'), validator: (v) => normalizePhone(v ?? '').length < 10 ? 'اكتب رقم صحيح' : null),
      const SizedBox(height: 12),
      TextFormField(
        controller: _nationalId,
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        maxLength: 14,
        decoration: const InputDecoration(labelText: 'الرقم القومي (14 رقم) *', counterText: ''),
        validator: (v) => RegExp(r'^[23]\d{13}$').hasMatch(latinDigits(v ?? '').trim()) ? null : 'الرقم القومي 14 رقم',
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _photoBusy ? null : _photo,
        icon: _photoBusy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(_photoId == null ? Icons.photo_camera_rounded : Icons.check_circle_rounded, color: _photoId == null ? null : const Color(0xFF16A34A)),
        label: Text(_photoId == null ? 'صوّر البطاقة *' : 'اتصورت البطاقة ✓ (صورة تانية؟)'),
      ),
    ]);
    final price = SectionCard(title: 'السعر', icon: Icons.payments_rounded, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: MoneyField(controller: _cost, label: 'هتدفع للبائع *', validator: (c) => (c ?? 0) <= 0 ? 'اكتب المبلغ' : null)),
        const SizedBox(width: 12),
        Expanded(child: MoneyField(controller: _price, label: 'هتبيعه بكام؟')),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.other))
          ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
      ]),
    ]);

    return Scaffold(
      appBar: AppBar(title: const Text('شرا موبايل مستعمل')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: device),
              const SizedBox(width: 12),
              Expanded(child: Column(children: [seller, const SizedBox(height: 12), price])),
            ])
          else ...[device, const SizedBox(height: 12), seller, const SizedBox(height: 12), price],
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(width: wide ? 320 : double.infinity, child: BusyButton(label: 'تسجيل الشرا', icon: Icons.check_rounded, busy: _busy, onPressed: _save)),
          ),
        ]),
      ),
    );
  }
}

/// إضافة أجهزة لموديل موجود (رصيد أول المدة أو بضاعة من غير فاتورة).
class AddUnitsDialog extends ConsumerStatefulWidget {
  const AddUnitsDialog({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<AddUnitsDialog> createState() => _AddUnitsDialogState();
}

class _AddUnitsDialogState extends ConsumerState<AddUnitsDialog> {
  final _imei = TextEditingController();
  final _color = TextEditingController();
  final _imeis = <String>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _imei.dispose();
    _color.dispose();
    super.dispose();
  }

  void _add(String v) {
    final x = latinDigits(v.trim());
    if (x.length < 8 || _imeis.contains(x)) return;
    setState(() => _imeis.add(x));
    _imei.clear();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/units', {
        'productId': widget.product.id,
        'units': [for (final i in _imeis) {'imei': i, 'color': _color.text}],
      });
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'اتضاف ${_imeis.length} جهاز');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('إضافة أجهزة: ${widget.product.name}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('امسح الـ IMEI بتاع كل جهاز (من على العلبة) واحد ورا التاني.'),
          const SizedBox(height: 8),
          TextField(
            controller: _imei,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'IMEI',
              suffixIcon: cameraScanSupported
                  ? IconButton(
                      icon: const Icon(Icons.photo_camera_rounded),
                      onPressed: () async {
                        final c = await scanBarcode(context);
                        if (c != null) _add(c);
                      },
                    )
                  : null,
            ),
            onSubmitted: _add,
          ),
          const SizedBox(height: 8),
          TextField(controller: _color, decoration: const InputDecoration(labelText: 'اللون (لكلهم)')),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final i in _imeis) InputChip(label: Text(i), onDeleted: () => setState(() => _imeis.remove(i))),
          ]),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 140, child: BusyButton(label: 'إضافة ${_imeis.length}', busy: _busy, onPressed: _imeis.isEmpty ? null : _save)),
      ],
    );
  }
}
