import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/messages.dart';
import '../../core/session.dart';
import '../../core/shop.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';

/// إمتى تتبعت رسالة للعميل، وبأنهي طريقة، ونص كل رسالة.
class MessageSettingsScreen extends ConsumerWidget {
  const MessageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shop = ref.watch(shopProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('رسائل العملاء')),
      body: shop.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
        data: (s) => _MessagesForm(shop: s),
      ),
    );
  }
}

class _MessagesForm extends ConsumerStatefulWidget {
  const _MessagesForm({required this.shop});
  final ShopProfile shop;

  @override
  ConsumerState<_MessagesForm> createState() => _MessagesFormState();
}

class _MessagesFormState extends ConsumerState<_MessagesForm> {
  late final Map<MessageEvent, MessageRule> _rules = {
    for (final e in MessageEvent.automatic) e: widget.shop.ruleFor(e),
  };
  late final Map<MessageEvent, TextEditingController> _templates = {
    for (final e in MessageEvent.values) e: TextEditingController(text: widget.shop.templates[e.name] ?? defaultTemplates[e.name]),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _templates.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider).value!.api!.patch('/api/shop', {
        'rules': {for (final e in _rules.entries) e.key.name: e.value.name},
        'templates': {for (final e in _templates.entries) e.key.name: e.value.text},
      });
      ref.invalidate(shopProvider);
      if (mounted) showMessage(context, 'تم حفظ إعدادات الرسائل');
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _preview(String template) => renderTemplate(template, {
        'customer': 'أحمد علي',
        'device': 'Samsung Galaxy A55',
        'number': '1042',
        'pin': '4821',
        'status': 'جاري الإصلاح',
        'due': 'بكرة، 6:00 م',
        'total': '2,500 ج.م',
        'paid': '500 ج.م',
        'remaining': '2,000 ج.م',
        'link': widget.shop.trackingLink('...'),
        'shop': widget.shop.name,
        'shop_phone': widget.shop.phone,
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('طرق الإرسال', style: const TextStyle().bold),
                        const SizedBox(height: 6),
                        const Text('• واتساب (بزرار): البرنامج بيفتح واتساب والرسالة مكتوبة، والموظف يدوس إرسال. مجاني.'),
                        const Text('• SMS أوتوماتيك: بتتبعت لوحدها من شريحة موبايل المحل اللي مفعّل عليه "بوابة SMS" (من الإعدادات على الموبايل). بتتحسب من باقة الشريحة.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final e in MessageEvent.values) ...[
                  SectionCard(
                    title: e.label,
                    icon: switch (e) {
                      MessageEvent.received => Icons.move_to_inbox_rounded,
                      MessageEvent.ready => Icons.check_circle_rounded,
                      MessageEvent.waitingParts => Icons.inventory_2_rounded,
                      MessageEvent.approval => Icons.price_change_rounded,
                      MessageEvent.dueChanged => Icons.event_rounded,
                      MessageEvent.delivered => Icons.handshake_rounded,
                      MessageEvent.reminder => Icons.notifications_active_rounded,
                      MessageEvent.custom => Icons.edit_note_rounded,
                    },
                    children: [
                      if (e != MessageEvent.custom) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<MessageRule>(
                            segments: [for (final r in MessageRule.values) ButtonSegment(value: r, label: Text(r.label))],
                            selected: {_rules[e]!},
                            onSelectionChanged: (s) => setState(() => _rules[e] = s.first),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (e == MessageEvent.custom || _rules[e] != MessageRule.off) ...[
                        TextField(
                          controller: _templates[e],
                          minLines: 3,
                          maxLines: 10,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(labelText: 'نص الرسالة', alignLabelWithHint: true),
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final v in templateVariables.entries)
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(v.value, style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                final c = _templates[e]!;
                                final pos = c.selection.isValid ? c.selection.start : c.text.length;
                                c.text = c.text.replaceRange(pos, pos, '{${v.key}}');
                                c.selection = TextSelection.collapsed(offset: pos + v.key.length + 2);
                                setState(() {});
                              },
                            ),
                        ]),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF25D366).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('شكلها عند العميل:', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              Text(_preview(_templates[e]!.text)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _templates[e]!.text = defaultTemplates[e.name]!),
                          child: const Text('رجّع النص الأصلي'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 12)],
                BusyButton(label: 'حفظ', icon: Icons.check_rounded, busy: _busy, onPressed: _save),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
