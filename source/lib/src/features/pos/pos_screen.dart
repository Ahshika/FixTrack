import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/session.dart';
import '../../core/shop.dart';
import '../../core/theme.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';
import '../../widgets/barcode_scan.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../inventory/products_screen.dart';
import '../phones/phones_screen.dart';
import '../receipts/print_service.dart';
import 'cart.dart';
import 'providers.dart';

/// شاشة الكاشير: مسح باركود أو بحث ← السلة ← الدفع ← الفاتورة.
class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  String? _category;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  CartController get _cart => ref.read(cartProvider.notifier);

  /// Enter في خانة البحث: لو باركود مظبوط يتضاف على طول (ده اللي بيحصل مع سكانر USB).
  Future<void> _submit(String value) async {
    final v = latinDigits(value.trim());
    if (v.isEmpty) return;
    final api = ref.read(sessionProvider).value!.api!;
    try {
      final res = await api.get('/api/products/lookup', query: {'barcode': v});
      if (res['product'] != null) {
        final unit = res['unit'] == null ? null : PhoneUnit(res['unit'] as Map<String, dynamic>);
        await _addProduct(Product(res['product'] as Map<String, dynamic>), unit: unit);
        _search.clear();
        setState(() => _query = '');
      } else {
        final found = await api.get('/api/products', query: {'q': v, 'limit': '2'});
        final list = (found['products'] as List).map((j) => Product(j as Map<String, dynamic>)).toList();
        if (list.length == 1) {
          _addProduct(list.first);
          _search.clear();
          setState(() => _query = '');
        } else if (list.isEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('مفيش صنف بالباركود ده: $v'),
            action: SnackBarAction(label: 'إضافة صنف', onPressed: () => addProductWithBarcode(context, v)),
          ));
        }
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    }
    _searchFocus.requestFocus();
  }

  Future<void> _addProduct(Product p, {PhoneUnit? unit}) async {
    if (p.serialized && unit == null) {
      unit = await showDialog<PhoneUnit>(context: context, builder: (_) => UnitPickerDialog(product: p));
      if (unit == null) return;
    }
    _cart.add(p, unit: unit);
    if (p.outOfStock && mounted) showMessage(context, 'تنبيه: "${p.name}" مفيش منه في المخزون حسب البرنامج');
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code != null) await _submit(code);
  }

  Future<void> _pay() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;
    final saleId = await showDialog<String>(context: context, builder: (_) => const _PaymentDialog());
    if (saleId == null || !mounted) return;
    _cart.clear();
    _searchFocus.requestFocus();
    if (ref.read(_autoPrintProvider)) {
      await printSale(context, ref, saleId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('تم البيع ✅'),
        action: SnackBarAction(label: 'طباعة الفاتورة', onPressed: () => printSale(context, ref, saleId)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final cart = ref.watch(cartProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f9): _pay,
        const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocus.requestFocus(),
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الكاشير'),
          actions: [
            if (!cart.isEmpty)
              TextButton.icon(
                onPressed: () => _cart.clear(),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: const Text('فاتورة جديدة'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _productsPanel()),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 420, child: _CartPanel(onPay: _pay)),
                ],
              )
            : _productsPanel(),
        bottomNavigationBar: wide || cart.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: const Text('الفاتورة')), body: _CartPanel(onPay: () async {
                        Navigator.pop(context);
                        await _pay();
                      }))),
                    ),
                    child: Text('الفاتورة (${cart.itemsCount}) • ${money(cart.totalCents)}'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _productsPanel() {
    final products = ref.watch(productsProvider((q: _query, category: _category, low: false)));
    final categories = ref.watch(categoriesProvider).value ?? const <String>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: cameraScanSupported ? 'امسح الباركود أو اكتب اسم الصنف' : 'امسح الباركود أو اكتب اسم الصنف (F2)',
              prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
              suffixIcon: cameraScanSupported
                  ? IconButton(tooltip: 'مسح بالكاميرا', icon: const Icon(Icons.photo_camera_rounded), onPressed: _scan)
                  : null,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = v.trim()));
            },
            onSubmitted: _submit,
          ),
        ),
        if (categories.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(label: const Text('الكل'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
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
          child: products.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
            data: (r) => r.items.isEmpty
                ? Center(
                    child: Text(_query.isEmpty ? 'لسه مفيش أصناف. ضيفها من شاشة "المخزون".' : 'مفيش صنف بالاسم ده',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, mainAxisExtent: 104, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: r.items.length,
                    itemBuilder: (context, i) => _ProductTile(product: r.items[i], onTap: () => _addProduct(r.items[i])),
                  ),
          ),
        ),
      ],
    );
  }
}

final _autoPrintProvider = NotifierProvider<_AutoPrint, bool>(_AutoPrint.new);

class _AutoPrint extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) => state = v;
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = product;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.3).semiBold),
              const Spacer(),
              Row(
                children: [
                  Expanded(child: Text(money(p.priceCents), style: TextStyle(color: scheme.primary).bold)),
                  if (p.trackStock)
                    Text(
                      '${p.qty}',
                      style: TextStyle(fontSize: 12, color: p.isLow ? scheme.error : scheme.onSurfaceVariant).semiBold,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  const _CartPanel({required this.onPay});
  final Future<void> Function() onPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final ctrl = ref.read(cartProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shop = ref.watch(shopProvider).value;
    final canDiscount = ref.watch(sessionProvider).value!.user!.isOwner || (shop?.cashierCanDiscount ?? true);

    return Material(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline_rounded),
            title: Text(cart.customer?.name ?? 'عميل نقدي'),
            subtitle: cart.customer != null ? Text(cart.customer!.phone) : const Text('اختار عميل للبيع الآجل أو عشان يتسجل عليه'),
            trailing: cart.customer != null
                ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => ctrl.setCustomer(null))
                : const Icon(Icons.chevron_left_rounded),
            onTap: () async {
              final c = await showDialog<Customer>(context: context, builder: (_) => const CustomerPickerDialog());
              if (c != null) ctrl.setCustomer(c);
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: cart.isEmpty
                ? Center(child: Text('الفاتورة فاضية', style: TextStyle(color: scheme.onSurfaceVariant)))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final l = cart.lines[i];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle().semiBold),
                                  if (l.unit != null)
                                    Text('IMEI ${l.unit!.imei}${l.unit!.details.isNotEmpty ? ' • ${l.unit!.details}' : ''}', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  InkWell(
                                    onTap: canDiscount
                                        ? () async {
                                            final cents = await _askMoney(context, 'سعر "${l.product.name}"', l.unitPriceCents);
                                            if (cents != null) ctrl.setPrice(l, cents);
                                          }
                                        : null,
                                    child: Text(
                                      '${money(l.unitPriceCents)}${l.unitPriceCents != l.product.priceCents ? ' (بدل ${money(l.product.priceCents)})' : ''}',
                                      style: TextStyle(fontSize: 12, color: l.unitPriceCents < l.product.priceCents ? brandOrange : scheme.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.remove_circle_outline_rounded), onPressed: () => ctrl.setQty(l, l.qty - 1)),
                            InkWell(
                              onTap: () async {
                                final q = await _askInt(context, 'الكمية', l.qty);
                                if (q != null) ctrl.setQty(l, q);
                              },
                              child: SizedBox(width: 30, child: Text('${l.qty}', textAlign: TextAlign.center, style: text.titleMedium?.bold)),
                            ),
                            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => ctrl.setQty(l, l.qty + 1)),
                            SizedBox(width: 78, child: Text(money(l.totalCents), textAlign: TextAlign.end, style: const TextStyle().semiBold)),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const Expanded(child: Text('الإجمالي')),
                  Text(money(cart.subtotalCents)),
                ]),
                Row(children: [
                  const Expanded(child: Text('خصم')),
                  TextButton(
                    onPressed: canDiscount && !cart.isEmpty
                        ? () async {
                            final c = await _askMoney(context, 'خصم على الفاتورة', cart.discountCents);
                            if (c != null) ctrl.setDiscount(c.clamp(0, cart.subtotalCents));
                          }
                        : null,
                    child: Text(cart.discountCents > 0 ? '- ${money(cart.discountCents)}' : 'إضافة خصم'),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: Text('المطلوب', style: text.titleLarge?.bold)),
                  Text(money(cart.totalCents), style: text.headlineSmall?.bold.copyWith(color: scheme.primary)),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: cart.isEmpty ? null : onPay,
                    icon: const Icon(Icons.payments_rounded),
                    label: Text(cameraScanSupported ? 'دفع' : 'دفع (F9)', style: text.titleMedium?.bold.copyWith(color: Colors.white)),
                  ),
                ),
                Consumer(builder: (context, ref, _) {
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: ref.watch(_autoPrintProvider),
                    onChanged: (v) => ref.read(_autoPrintProvider.notifier).set(v ?? true),
                    title: const Text('اطبع الفاتورة بعد البيع على طول'),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<int?> _askMoney(BuildContext context, String title, int initial) async {
  final c = TextEditingController(text: initial > 0 ? moneyInput(initial) : '');
  final r = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: MoneyField(controller: c, label: 'المبلغ', autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, parseMoney(c.text)), child: const Text('تمام')),
      ],
    ),
  );
  c.dispose();
  return r;
}

Future<int?> _askInt(BuildContext context, String title, int initial) async {
  final c = TextEditingController(text: '$initial');
  final r = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        onSubmitted: (v) => Navigator.pop(context, int.tryParse(latinDigits(v))),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(latinDigits(c.text))), child: const Text('تمام')),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// الدفع: كاش (ويحسب الباقي للزبون) أو محفظة أو فيزا، أو جزء والباقي آجل على العميل.
class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog();

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  PaymentMethod _method = PaymentMethod.cash;
  final _received = TextEditingController();
  bool _credit = false;
  final _creditPaid = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _received.dispose();
    _creditPaid.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final cart = ref.read(cartProvider);
    final total = cart.totalCents;
    final paid = _credit ? (parseMoney(_creditPaid.text) ?? 0).clamp(0, total) : total;
    if (_credit && cart.customer == null) {
      setState(() => _error = 'البيع الآجل لازم يكون على عميل. اقفل واختار العميل من فوق الفاتورة');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/sales', {
        'customerId': cart.customer?.id,
        'items': [
          for (final l in cart.lines) {'productId': l.product.id, 'qty': l.qty, 'unitPriceCents': l.unitPriceCents, 'unitId': ?l.unit?.id},
        ],
        'discountCents': cart.discountCents,
        'payments': [if (paid > 0) {'method': _method.name, 'amountCents': paid}],
      });
      if (mounted) Navigator.pop(context, (res['sale'] as Map)['id'] as String);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final total = cart.totalCents;
    final text = Theme.of(context).textTheme;
    final received = parseMoney(_received.text) ?? 0;
    final change = received - total;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): () => _busy ? null : _confirm()},
      child: AlertDialog(
        title: Text('المطلوب: ${money(total)}', style: text.headlineSmall?.bold),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in PaymentMethod.values.where((m) => m != PaymentMethod.other))
                    ChoiceChip(label: Text(m.label), selected: _method == m, onSelected: (_) => setState(() => _method = m)),
                ]),
                const SizedBox(height: 16),
                if (!_credit && _method == PaymentMethod.cash) ...[
                  MoneyField(controller: _received, label: 'الزبون دفع كام؟ (اختياري)', autofocus: true, onChanged: (_) => setState(() {})),
                  const SizedBox(height: 8),
                  if (received > 0)
                    Text(
                      change >= 0 ? 'الباقي للزبون: ${money(change)}' : 'ناقص ${money(-change)}',
                      style: text.titleLarge?.bold.copyWith(color: change >= 0 ? const Color(0xFF16A34A) : Theme.of(context).colorScheme.error),
                    ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _credit,
                  onChanged: (v) => setState(() => _credit = v ?? false),
                  title: const Text('آجل (العميل هيدفع جزء أو مش هيدفع دلوقتي)'),
                  subtitle: Text(cart.customer == null ? 'لازم تختار العميل الأول' : 'على: ${cart.customer!.name}'),
                ),
                if (_credit) ...[
                  MoneyField(controller: _creditPaid, label: 'المدفوع دلوقتي', onChanged: (_) => setState(() {})),
                  const SizedBox(height: 6),
                  Text('هيتسجل على العميل: ${money((total - (parseMoney(_creditPaid.text) ?? 0)).clamp(0, total))}', style: const TextStyle().semiBold),
                ],
                if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('رجوع')),
          SizedBox(width: 160, child: BusyButton(label: 'تأكيد (Enter)', busy: _busy, onPressed: _confirm)),
        ],
      ),
    );
  }
}

/// اختيار عميل (بحث بالاسم أو الرقم) أو إضافة عميل جديد بسرعة.
class CustomerPickerDialog extends ConsumerStatefulWidget {
  const CustomerPickerDialog({super.key});

  @override
  ConsumerState<CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends ConsumerState<CustomerPickerDialog> {
  final _q = TextEditingController();
  final _name = TextEditingController();
  List<Customer> _results = [];
  Timer? _debounce;
  bool _adding = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _search(String v) async {
    final res = await ref.read(sessionProvider).value!.api!.get('/api/customers', query: {'q': v, 'limit': '20'});
    if (mounted) setState(() => _results = (res['customers'] as List).map((j) => Customer.fromJson(j as Map<String, dynamic>)).toList());
  }

  Future<void> _add() async {
    setState(() => _error = null);
    try {
      final res = await ref.read(sessionProvider).value!.api!.post('/api/customers', {'name': _name.text, 'phone': _q.text});
      if (mounted) Navigator.pop(context, Customer.fromJson(res['customer'] as Map<String, dynamic>));
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختيار عميل'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'اسم العميل أو رقم تليفونه', prefixIcon: Icon(Icons.search_rounded)),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final c in _results)
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.phone),
                    onTap: () => Navigator.pop(context, c),
                  ),
                if (_q.text.trim().isNotEmpty && !_adding)
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: const Text('عميل جديد'),
                    onTap: () => setState(() => _adding = true),
                  ),
                if (_adding) ...[
                  const SizedBox(height: 8),
                  Text('رقم التليفون: ${_q.text}', style: const TextStyle().semiBold),
                  const SizedBox(height: 8),
                  TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'اسم العميل'), onSubmitted: (_) => _add()),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _add, child: const Text('إضافة واختيار')),
                ],
                if (_error != null) ...[const SizedBox(height: 8), ErrorBanner(_error!)],
              ]),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء'))],
    );
  }
}
