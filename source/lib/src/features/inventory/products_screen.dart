import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/barcode_scan.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/suggest_field.dart';
import '../../widgets/ticket_widgets.dart';
import '../pos/providers.dart';
import '../receipts/print_service.dart';
import '../phones/phones_screen.dart';
import 'import_screen.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _category;
  bool _lowOnly = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).value!.user!;
    final data = ref.watch(productsProvider((q: _query, category: _category, low: _lowOnly)));
    final categories = ref.watch(categoriesProvider).value ?? const <String>[];
    final scheme = Theme.of(context).colorScheme;
    final r = data.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المخزون'),
        actions: [
          if (user.isOwner)
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ImportScreen())),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('استيراد من Excel'),
            ),
          IconButton(
            tooltip: 'طباعة باركود',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: r == null || r.items.isEmpty
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _LabelsDialog(products: r.items.where((p) => p.barcode != null).toList()),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const ProductDialog()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('صنف جديد'),
      ),
      body: Column(
        children: [
          if (r != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text('${r.count} صنف', style: const TextStyle().semiBold),
                  if (r.lowCount > 0)
                    InkWell(
                      onTap: () => setState(() => _lowOnly = !_lowOnly),
                      child: Text('${r.lowCount} قرّب يخلص', style: TextStyle(color: scheme.error).semiBold),
                    ),
                  if (r.stockValueCents != null) Text('قيمة البضاعة (بسعر الشرا): ${money(r.stockValueCents!)}'),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'دوّر بالاسم أو الباركود',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: cameraScanSupported
                    ? IconButton(
                        icon: const Icon(Icons.photo_camera_rounded),
                        onPressed: () async {
                          final code = await scanBarcode(context);
                          if (code != null) {
                            _search.text = code;
                            setState(() => _query = code);
                          }
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
              },
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: FilterChip(label: const Text('قرّب يخلص'), selected: _lowOnly, onSelected: (v) => setState(() => _lowOnly = v)),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: const Text('كل الأقسام'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                ),
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: data.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
              ),
              data: (r) => r.items.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: _query.isEmpty && _category == null && !_lowOnly
                          ? 'لسه مفيش أصناف.\nضيف صنف جديد، أو استورد الأصناف من ملف Excel من برنامجك القديم.'
                          : 'مفيش أصناف هنا',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                      itemCount: r.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) => _ProductRow(product: r.items[i], showCost: user.isOwner),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.showCost});
  final Product product;
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(p.name, style: const TextStyle().semiBold),
        subtitle: Text([?p.category, if (p.barcode != null) p.barcode!, if (showCost) 'شرا ${money(p.costCents)}'].join(' • ')),
        leading: p.trackStock && !p.serialized
            ? IconButton.filledTonal(
                tooltip: 'إضافة كمية وصلت',
                icon: const Icon(Icons.add_rounded),
                onPressed: () => showDialog<void>(context: context, builder: (_) => AddStockDialog(product: p)),
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(p.priceCents), style: TextStyle(color: scheme.primary).bold),
            if (p.trackStock)
              Text(
                p.outOfStock ? 'خلصان' : 'متاح ${p.qty}',
                style: TextStyle(fontSize: 12, color: p.isLow ? scheme.error : scheme.onSurfaceVariant).semiBold,
              ),
          ],
        ),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => ProductDialog(product: p),
        ),
      ),
    );
  }
}

/// إضافة صنف أو تعديله، ومنه الجرد وحركة المخزون.
class ProductDialog extends ConsumerStatefulWidget {
  const ProductDialog({super.key, this.product, this.initialBarcode});
  final Product? product;
  final String? initialBarcode;

  @override
  ConsumerState<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<ProductDialog> {
  final _form = GlobalKey<FormState>();
  late final p = widget.product;
  late final _name = TextEditingController(text: p?.name);
  late final _barcode = TextEditingController(text: p?.barcode ?? widget.initialBarcode);
  late final _category = TextEditingController(text: p?.category);
  late final _cost = TextEditingController(text: p == null ? '' : moneyInput(p!.costCents));
  late final _price = TextEditingController(text: p == null ? '' : moneyInput(p!.priceCents));
  late final _qty = TextEditingController(text: p == null ? '' : '${p!.qty}');
  late final _low = TextEditingController(text: '${p?.lowStock ?? 2}');
  late bool _track = p?.trackStock ?? true;
  late bool _serialized = p?.serialized ?? false;
  late final _warranty = TextEditingController(text: '${p?.warrantyMonths ?? 0}');
  bool _busy = false;
  String? _error;

  bool get _isNew => p == null;

  @override
  void dispose() {
    for (final c in [_name, _barcode, _category, _cost, _price, _qty, _low, _warranty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _generateBarcode() async {
    final res = await ref.read(sessionProvider).value!.api!.post('/api/products/barcode');
    setState(() => _barcode.text = res['barcode'] as String);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final isOwner = ref.read(sessionProvider).value!.user!.isOwner;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(sessionProvider).value!.api!;
    try {
      final body = {
        'name': _name.text,
        'barcode': _barcode.text,
        'category': _category.text,
        if (isOwner || _isNew) 'costCents': parseMoney(_cost.text) ?? 0,
        'priceCents': parseMoney(_price.text) ?? 0,
        'lowStock': int.tryParse(latinDigits(_low.text)) ?? 0,
        'trackStock': _track,
        'serialized': _serialized,
        'warrantyMonths': int.tryParse(latinDigits(_warranty.text)) ?? 0,
      };
      if (_isNew) {
        await api.post('/api/products', {...body, 'qty': int.tryParse(latinDigits(_qty.text)) ?? 0});
      } else {
        await api.patch('/api/products/${p!.id}', body);
        final newQty = int.tryParse(latinDigits(_qty.text));
        if (isOwner && newQty != null && newQty != p!.qty) {
          await api.post('/api/products/${p!.id}/adjust', {'setQty': newQty, 'reason': 'count', 'note': 'تعديل من شاشة الصنف'});
        }
      }
      ref.invalidate(productsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, _isNew ? 'اتضاف "${_name.text}"' : 'اتحفظ');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    await ref.read(sessionProvider).value!.api!.patch('/api/products/${p!.id}', {'active': false});
    ref.invalidate(productsProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).value!.user!;
    final categories = ref.watch(categoriesProvider).value ?? const <String>[];
    final canEditQty = _isNew || user.isOwner;
    return AlertDialog(
      title: Text(_isNew ? 'صنف جديد' : p!.name),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: _isNew,
                  decoration: const InputDecoration(labelText: 'اسم الصنف *'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'اكتب اسم الصنف' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcode,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'الباركود (امسحه بالسكانر أو سيبه فاضي)',
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cameraScanSupported)
                          IconButton(
                            icon: const Icon(Icons.photo_camera_rounded),
                            onPressed: () async {
                              final c = await scanBarcode(context);
                              if (c != null) setState(() => _barcode.text = c);
                            },
                          ),
                        IconButton(tooltip: 'اعمل باركود جديد', icon: const Icon(Icons.auto_awesome_rounded), onPressed: _generateBarcode),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SuggestField(controller: _category, label: 'القسم (مثلاً: جرابات، شواحن)', options: () => categories),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user.isOwner || _isNew) ...[
                      Expanded(
                        child: MoneyField(controller: _cost, label: 'سعر الشرا'),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: MoneyField(controller: _price, label: 'سعر البيع *', validator: (c) => (c ?? 0) <= 0 ? 'اكتب السعر' : null),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('موبايل / جهاز له IMEI'),
                  subtitle: const Text('كل جهاز بيتسجل ويتباع بالـ IMEI بتاعه'),
                  value: _serialized,
                  onChanged: p?.serialized == true ? null : (v) => setState(() => _serialized = v),
                ),
                TextFormField(
                  controller: _warranty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'الضمان بالشهور (0 = من غير ضمان)'),
                ),
                if (!_serialized)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('متابعة الكمية في المخزون'),
                    subtitle: const Text('اقفلها للخدمات أو الحاجات اللي مالهاش عدد'),
                    value: _track,
                    onChanged: (v) => setState(() => _track = v),
                  ),
                if (_serialized && !_isNew)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => AddUnitsDialog(product: p!),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: Text('الأجهزة: ${p!.qty} في المحل • إضافة بالـ IMEI'),
                    ),
                  ),
                if (_track && !_serialized)
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _qty,
                          enabled: canEditQty,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: _isNew ? 'الكمية الموجودة' : 'الكمية (الجرد)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _low,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'نبّهني لما يوصل لـ'),
                        ),
                      ),
                    ],
                  ),
                if (!_isNew && _track && !_serialized) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await showDialog<void>(context: context, builder: (_) => AddStockDialog(product: p!));
                      },
                      icon: const Icon(Icons.add_box_rounded),
                      label: Text('إضافة كمية وصلت (الموجود ${p!.qty})'),
                    ),
                  ),
                ],
                if (!_isNew && user.isOwner) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _MovesDialog(product: p!),
                      ),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('حركة الصنف'),
                    ),
                  ),
                ],
                if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!_isNew && user.isOwner)
          TextButton(
            onPressed: _busy ? null : _archive,
            child: Text('إيقاف الصنف', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(
          width: 120,
          child: BusyButton(label: 'حفظ', busy: _busy, onPressed: _save),
        ),
      ],
    );
  }
}

/// إضافة كمية وصلت: بيظهر الموجود، وتكتب الجديد، والإجمالي بيتحسب قدامك، ولما تحفظ بيتجمعوا.
class AddStockDialog extends ConsumerStatefulWidget {
  const AddStockDialog({super.key, required this.product});
  final Product product;

  @override
  ConsumerState<AddStockDialog> createState() => _AddStockDialogState();
}

class _AddStockDialogState extends ConsumerState<AddStockDialog> {
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  int? get _added {
    final v = int.tryParse(latinDigits(_qty.text.trim()));
    return v == null || v <= 0 ? null : v;
  }

  Future<void> _save() async {
    final added = _added;
    if (added == null) return setState(() => _error = 'اكتب العدد اللي وصل');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cost = parseMoney(_cost.text);
      final res = await ref.read(sessionProvider).value!.api!.post('/api/products/${widget.product.id}/adjust', {
        'qtyChange': added,
        'reason': 'purchase',
        'note': 'كمية وصلت',
        if (cost != null && cost > 0) 'costCents': cost,
      });
      ref.invalidate(productsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, '${widget.product.name}: بقى ${(res['product'] as Map)['qty']}');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final added = _added;
    final isOwner = ref.watch(sessionProvider).value!.user!.isOwner;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget box(String label, String value, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(label, style: text.bodySmall),
              Text(value, style: text.titleLarge?.bold.copyWith(color: color), textAlign: TextAlign.center),
            ]),
          ),
        );
    return AlertDialog(
      title: Text('إضافة كمية: ${p.name}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            box('كان عندك', '${p.qty}', scheme.outline),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.add_rounded)),
            box('وصل', added == null ? '—' : '$added', brandOrange),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('=', style: TextStyle(fontSize: 22))),
            box('هيبقى', '${p.qty + (added ?? 0)}', scheme.primary),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'العدد الجديد اللي وصل'),
          ),
          if (isOwner) ...[
            const SizedBox(height: 10),
            MoneyField(controller: _cost, label: 'دفعت فيهم كام؟ (اختياري، عشان سعر الشرا يتحدث)'),
          ],
          if (_error != null) ...[const SizedBox(height: 10), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'حفظ', busy: _busy, onPressed: _save)),
      ],
    );
  }
}

const _moveReasons = {
  'initial': 'رصيد أول المدة',
  'sale': 'بيع',
  'return': 'مرتجع من عميل',
  'purchase': 'شرا / وارد',
  'count': 'جرد',
  'damaged': 'تالف',
  'lost': 'فاقد',
  'return_supplier': 'مرتجع للمورد',
  'import': 'استيراد',
  'repair': 'صيانة',
  'transfer_out': 'تحويل لفرع تاني',
  'transfer_in': 'تحويل من فرع تاني',
  'other': 'أخرى',
};

class _MovesDialog extends ConsumerWidget {
  const _MovesDialog({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(sessionProvider).value!.api!;
    return AlertDialog(
      title: Text('حركة: ${product.name}'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: FutureBuilder(
          future: api.get('/api/products/${product.id}/moves'),
          builder: (context, snap) {
            if (snap.hasError) return ErrorBanner(errorText(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final moves = (snap.data!['moves'] as List).cast<Map<String, dynamic>>();
            if (moves.isEmpty) return const Center(child: Text('مفيش حركة'));
            return ListView.separated(
              itemCount: moves.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = moves[i];
                final change = m['change'] as int;
                return ListTile(
                  dense: true,
                  leading: Text(
                    change > 0 ? '+$change' : '$change',
                    style: TextStyle(color: change > 0 ? const Color(0xFF16A34A) : Theme.of(context).colorScheme.error).bold,
                  ),
                  title: Text(_moveReasons[m['reason']] ?? '${m['reason']}'),
                  subtitle: Text(
                    '${formatDateTime(parseDate(m['createdAt'])!)}${m['userName'] != null ? ' • ${m['userName']}' : ''}${m['note'] != null ? '\n${m['note']}' : ''}',
                  ),
                  trailing: Text('الرصيد ${m['after']}'),
                );
              },
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('قفل'))],
    );
  }
}

class _LabelsDialog extends ConsumerStatefulWidget {
  const _LabelsDialog({required this.products});
  final List<Product> products;

  @override
  ConsumerState<_LabelsDialog> createState() => _LabelsDialogState();
}

class _LabelsDialogState extends ConsumerState<_LabelsDialog> {
  late final Map<String, int> _copies = {for (final p in widget.products) p.id: 0};
  bool _a4 = false;

  @override
  Widget build(BuildContext context) {
    final total = _copies.values.fold<int>(0, (s, c) => s + c);
    return AlertDialog(
      title: const Text('طباعة ستيكرات باركود'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('طابعة ستيكر (50×30)')),
                ButtonSegment(value: true, label: Text('ورق A4')),
              ],
              selected: {_a4},
              onSelectionChanged: (s) => setState(() => _a4 = s.first),
            ),
            const SizedBox(height: 8),
            if (widget.products.isEmpty) const Expanded(child: Center(child: Text('مفيش أصناف ليها باركود في القايمة'))),
            Expanded(
              child: ListView(
                children: [
                  for (final p in widget.products)
                    ListTile(
                      dense: true,
                      title: Text(p.name),
                      subtitle: Text(p.barcode!, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_rounded),
                            onPressed: () => setState(() => _copies[p.id] = (_copies[p.id]! - 1).clamp(0, 999)),
                          ),
                          Text('${_copies[p.id]}'),
                          IconButton(icon: const Icon(Icons.add_rounded), onPressed: () => setState(() => _copies[p.id] = _copies[p.id]! + 1)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: total == 0
              ? null
              : () {
                  final items = [
                    for (final p in widget.products)
                      if (_copies[p.id]! > 0) (product: p, copies: _copies[p.id]!),
                  ];
                  Navigator.pop(context);
                  printBarcodeLabels(context, ref, items, a4: _a4);
                },
          child: Text('طباعة $total'),
        ),
      ],
    );
  }
}

/// بيستخدم في الكاشير لما باركود مش متسجل: يفتح شاشة صنف جديد بالباركود ده.
Future<void> addProductWithBarcode(BuildContext context, String barcode) => showDialog<void>(
  context: context,
  builder: (_) => ProductDialog(initialBarcode: barcode),
);
