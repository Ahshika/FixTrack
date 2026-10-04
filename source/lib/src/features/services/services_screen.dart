import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/pos_models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/ticket_widgets.dart';
import '../pos/providers.dart';

const _kindColors = {
  'vodafone': Color(0xFFE60000),
  'etisalat': Color(0xFF7AB800),
  'orange': Color(0xFFFF7900),
  'we': Color(0xFF5C2D91),
  'instapay': Color(0xFF3E1F7A),
  'fawry': Color(0xFF0F5FA8),
  'aman': Color(0xFF0B8F6A),
  'other': Color(0xFF64748B),
};

/// المحافظ الإلكترونية وخدمات الشحن: إيداع وسحب للعملاء، وشحن رصيد، ودفع فواتير، بعمولة.
class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(walletsProvider);
    final isOwner = ref.watch(sessionProvider).value!.user!.isOwner;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحافظ والخدمات'),
        actions: [
          if (isOwner)
            TextButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const _NewWalletDialog()),
              icon: const Icon(Icons.add_card_rounded),
              label: const Text('محفظة جديدة'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: data.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: ErrorBanner(errorText(e))),
        data: (d) => d.wallets.isEmpty
            ? EmptyState(
                icon: Icons.account_balance_wallet_outlined,
                message: isOwner ? 'ضيف محافظ المحل (فودافون كاش، إنستاباي، فوري...) عشان تسجل عليها العمليات والعمولات.' : 'صاحب المحل لسه ما ضافش محافظ.',
              )
            : ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.trending_up_rounded, color: Color(0xFF16A34A)),
                    title: const Text('عمولات النهارده'),
                    trailing: Text(money(d.todayCommissionCents), style: text.titleLarge?.bold),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(builder: (context, c) {
                  final cols = c.maxWidth >= 900 ? 3 : c.maxWidth >= 560 ? 2 : 1;
                  final w = (c.maxWidth - (cols - 1) * 12) / cols;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final wl in d.wallets) SizedBox(width: w, child: _WalletCard(wallet: wl)),
                  ]);
                }),
              ]),
      ),
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    final color = _kindColors[w.kind] ?? brandBlue;
    final text = Theme.of(context).textTheme;
    Widget action(String type, IconData icon) => OutlinedButton.icon(
          onPressed: () => showDialog<void>(context: context, builder: (_) => _TxnDialog(wallet: w, type: type)),
          icon: Icon(icon, size: 18),
          label: Text(walletTxnLabels[type]!),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: color,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.name, style: text.titleMedium?.bold.copyWith(color: Colors.white)),
            Text('${walletKindLabels[w.kind] ?? ''}${w.phone != null ? ' • ${w.phone}' : ''}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 8),
            Text(money(w.balanceCents), style: text.headlineSmall?.bold.copyWith(color: Colors.white)),
            Text('النهارده: ${w.todayCount} عملية • عمولة ${money(w.todayCommissionCents)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            action('cash_in', Icons.call_made_rounded),
            action('cash_out', Icons.call_received_rounded),
            action('recharge', Icons.phone_android_rounded),
            action('bill', Icons.receipt_rounded),
            action('topup', Icons.add_rounded),
            action('withdraw', Icons.outbox_rounded),
          ]),
        ),
        TextButton(
          onPressed: () => showDialog<void>(context: context, builder: (_) => _TxnsDialog(wallet: w)),
          child: const Text('العمليات'),
        ),
      ]),
    );
  }
}

class _TxnDialog extends ConsumerStatefulWidget {
  const _TxnDialog({required this.wallet, required this.type});
  final Wallet wallet;
  final String type;

  @override
  ConsumerState<_TxnDialog> createState() => _TxnDialogState();
}

class _TxnDialogState extends ConsumerState<_TxnDialog> {
  final _amount = TextEditingController();
  final _commission = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _customerFacing => const {'cash_in', 'cash_out', 'recharge', 'bill'}.contains(widget.type);

  @override
  void dispose() {
    _amount.dispose();
    _commission.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/wallets/${widget.wallet.id}/txns', {
        'type': widget.type,
        'amountCents': parseMoney(_amount.text),
        'commissionCents': parseMoney(_commission.text) ?? 0,
        'customerPhone': _phone.text,
      });
      ref.invalidate(walletsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseMoney(_amount.text) ?? 0;
    final commission = parseMoney(_commission.text) ?? 0;
    final hint = switch (widget.type) {
      'cash_in' => 'العميل هيدفعلك كاش ${money(amount + commission)}، وإنت تحوّل ${money(amount)} على محفظته',
      'cash_out' => 'العميل يحوّل ${money(amount)} على محفظتك، وإنت تديله كاش ${money(amount - commission)}',
      'recharge' || 'bill' => 'العميل هيدفعلك ${money(amount + commission)} كاش',
      'topup' => 'هتاخد ${money(amount)} من الدرج وتحطها في المحفظة',
      _ => 'هتسحب ${money(amount)} من المحفظة للدرج',
    };
    return AlertDialog(
      title: Text('${walletTxnLabels[widget.type]} • ${widget.wallet.name}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('رصيد المحفظة: ${money(widget.wallet.balanceCents)}'),
          const SizedBox(height: 12),
          MoneyField(controller: _amount, label: 'المبلغ', autofocus: true, onChanged: (_) => setState(() {})),
          if (_customerFacing) ...[
            const SizedBox(height: 12),
            MoneyField(controller: _commission, label: 'العمولة', onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم العميل (اختياري)')),
          ],
          if (amount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: brandBlue.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
              child: Text(hint, style: const TextStyle().semiBold),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        SizedBox(width: 120, child: BusyButton(label: 'تسجيل', busy: _busy, onPressed: amount > 0 ? _save : null)),
      ],
    );
  }
}

class _TxnsDialog extends ConsumerWidget {
  const _TxnsDialog({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(sessionProvider).value!.api!;
    return AlertDialog(
      title: Text('عمليات ${wallet.name}'),
      content: SizedBox(
        width: 480,
        height: 480,
        child: FutureBuilder(
          future: api.get('/api/wallets/${wallet.id}/txns'),
          builder: (context, snap) {
            if (snap.hasError) return ErrorBanner(errorText(snap.error!));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final txns = (snap.data!['txns'] as List).cast<Map<String, dynamic>>();
            if (txns.isEmpty) return const Center(child: Text('مفيش عمليات'));
            return ListView.separated(
              itemCount: txns.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = txns[i];
                return ListTile(
                  dense: true,
                  title: Text('${walletTxnLabels[t['type']] ?? t['type']} • ${money(t['amountCents'] as int)}'),
                  subtitle: Text([
                    formatDateTime(parseDate(t['createdAt'])!),
                    if ((t['commissionCents'] as int) > 0) 'عمولة ${money(t['commissionCents'] as int)}',
                    if (t['customerPhone'] != null) t['customerPhone'],
                    if (t['userName'] != null) t['userName'],
                  ].join(' • ')),
                  trailing: Text('الرصيد ${money(t['balanceAfter'] as int)}', style: const TextStyle(fontSize: 12)),
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

class _NewWalletDialog extends ConsumerStatefulWidget {
  const _NewWalletDialog();

  @override
  ConsumerState<_NewWalletDialog> createState() => _NewWalletDialogState();
}

class _NewWalletDialogState extends ConsumerState<_NewWalletDialog> {
  String _kind = 'vodafone';
  final _name = TextEditingController(text: 'فودافون كاش');
  final _phone = TextEditingController();
  final _balance = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/wallets', {
        'name': _name.text,
        'kind': _kind,
        'phone': _phone.text,
        'balanceCents': parseMoney(_balance.text) ?? 0,
      });
      ref.invalidate(walletsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('محفظة جديدة'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in walletKindLabels.entries)
              ChoiceChip(
                label: Text(k.value),
                selected: _kind == k.key,
                onSelected: (_) => setState(() {
                  _kind = k.key;
                  if (walletKindLabels.containsValue(_name.text) || _name.text.isEmpty) _name.text = k.value;
                }),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المحفظة')),
          const SizedBox(height: 12),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم المحفظة')),
          const SizedBox(height: 12),
          MoneyField(controller: _balance, label: 'الرصيد اللي فيها دلوقتي'),
          if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!)],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _save, child: const Text('إضافة')),
      ],
    );
  }
}
