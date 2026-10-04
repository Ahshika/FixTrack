import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/messages.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/shop.dart';
import '../../core/theme.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../../widgets/pattern_pad.dart';
import '../../widgets/ticket_widgets.dart';
import '../messages/message_dialog.dart';
import '../receipts/print_service.dart';
import 'providers.dart';
import 'ticket_dialogs.dart';
import 'ticket_parts.dart';

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ticketDetailProvider(ticketId));
    final user = ref.watch(sessionProvider).value!.user!;

    return detail.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
      ),
      data: (d) => _TicketView(detail: d, user: user),
    );
  }
}

class _TicketView extends ConsumerWidget {
  const _TicketView({required this.detail, required this.user});

  final TicketDetail detail;
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = detail.ticket;
    final isStaff = user.role != Role.technician;
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final main = [
      if (detail.warrantyOrigin != null) ...[
        WarrantyBanner(
          origin: detail.warrantyOrigin!,
          onOpen: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => TicketDetailScreen(ticketId: detail.warrantyOrigin!['id'] as String)),
          ),
        ),
        const SizedBox(height: 12),
      ],
      _HeaderCard(ticket: t),
      if (t.approvalPending) ...[const SizedBox(height: 12), _ApprovalCard(ticket: t, isStaff: isStaff)],
      const SizedBox(height: 12),
      _ProgressCard(ticket: t, user: user),
      const SizedBox(height: 12),
      _DetailsCard(ticket: t),
    ];
    final side = [
      _MoneyCard(detail: detail, canEdit: isStaff),
      const SizedBox(height: 12),
      PartsCard(detail: detail, user: user),
      const SizedBox(height: 12),
      if (detail.messages.isNotEmpty) ...[_MessagesCard(messages: detail.messages), const SizedBox(height: 12)],
      _TimelineCard(detail: detail),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('جهاز #${t.number}'),
        actions: [
          if (isStaff) ...[
            IconButton(
              tooltip: 'رسالة للعميل',
              icon: const Icon(Icons.chat_rounded),
              onPressed: () => showMessageDialog(
                context,
                t.id,
                MessageEvent.forStatus(t.status) ?? (t.status == TicketStatus.received ? MessageEvent.received : MessageEvent.custom),
              ),
            ),
            IconButton(
              tooltip: 'طباعة الوصل',
              icon: const Icon(Icons.print_rounded),
              onPressed: () => printTicket(context, ref, t.id, PrintKind.receipt),
            ),
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              onSelected: (v) => switch (v) {
                'sticker' => printTicket(context, ref, t.id, PrintKind.sticker),
                'share' => shareReceipt(context, ref, t.id),
                _ => null,
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'sticker', child: ListTile(leading: Icon(Icons.sell_rounded), title: Text('طباعة ستيكر للجهاز'))),
                PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('حفظ / مشاركة الوصل PDF'))),
              ],
            ),
          ],
          if (t.status != TicketStatus.delivered || user.isOwner)
            IconButton(
              tooltip: 'تعديل',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => showDialog<void>(context: context, builder: (_) => EditTicketDialog(ticket: t, user: user)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: wide
            ? [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: Column(children: main)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: Column(children: side)),
                  ],
                ),
              ]
            : [...main, const SizedBox(height: 12), ...side],
      ),
    );
  }
}

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ticket;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final link = ref.watch(shopProvider).value?.trackingLink(t.publicToken);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: statusColor(t.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(deviceIcon(t.deviceType), color: statusColor(t.status), size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.deviceName, style: text.titleLarge?.bold),
                      Text([deviceTypes[t.deviceType], ?t.color].join(' • '), style: muted),
                      const SizedBox(height: 8),
                      StatusChip(t.status),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _InfoItem(icon: Icons.person_rounded, label: 'العميل', value: t.customerName),
                _InfoItem(
                  icon: Icons.call_rounded,
                  label: 'التليفون',
                  value: t.customerPhone,
                  ltr: true,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: t.customerPhone));
                    showMessage(context, 'اتنسخ الرقم');
                  },
                ),
                _InfoItem(icon: Icons.engineering_rounded, label: 'الفني', value: t.technicianName ?? 'لسه محددش'),
                _InfoItem(
                  icon: t.overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                  label: 'الموعد المتوقع',
                  value: t.dueAt == null ? 'مش محدد' : formatDateTime(t.dueAt!),
                  color: t.overdue ? scheme.error : null,
                ),
                _InfoItem(icon: Icons.move_to_inbox_rounded, label: 'اتسلم', value: formatDateTime(t.createdAt)),
                if (t.pickupPin != null && t.status != TicketStatus.delivered)
                  _InfoItem(icon: Icons.pin_rounded, label: 'كود الاستلام', value: t.pickupPin!, ltr: true, color: brandOrange),
                if (t.deliveredAt != null)
                  _InfoItem(
                    icon: Icons.handshake_rounded,
                    label: 'اتسلم للعميل',
                    value: '${formatDateTime(t.deliveredAt!)}${t.deliveredByName != null ? ' • ${t.deliveredByName}' : ''}',
                  ),
                if (t.status == TicketStatus.delivered && t.warrantyUntil != null)
                  _InfoItem(
                    icon: Icons.verified_user_rounded,
                    label: 'الضمان',
                    value: t.underWarranty ? 'لحد ${formatDate(t.warrantyUntil!)}' : 'خلص ${formatDate(t.warrantyUntil!)}',
                    color: t.underWarranty ? const Color(0xFF16A34A) : scheme.onSurfaceVariant,
                  ),
                if (t.pickupAt != null && t.status != TicketStatus.delivered)
                  _InfoItem(
                    icon: Icons.event_available_rounded,
                    label: 'معاد الاستلام',
                    value: formatDateTime(t.pickupAt!),
                    color: const Color(0xFF16A34A),
                  ),
              ],
            ),
            if (link != null && t.status != TicketStatus.delivered) ...[
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: link));
                  showMessage(context, 'اتنسخ لينك المتابعة، تقدر تبعته للعميل');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(Icons.link_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text('نسخ لينك متابعة العميل', style: TextStyle(color: scheme.primary).semiBold),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({required this.icon, required this.label, required this.value, this.ltr = false, this.color, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final bool ltr;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color ?? scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            Text(value, textDirection: ltr ? TextDirection.ltr : null, style: TextStyle(color: color).semiBold),
          ],
        ),
      ],
    );
    return onTap == null ? child : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: child);
  }
}

class _ProgressCard extends ConsumerStatefulWidget {
  const _ProgressCard({required this.ticket, required this.user});
  final Ticket ticket;
  final AppUser user;

  @override
  ConsumerState<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<_ProgressCard> {
  bool _busy = false;

  Future<void> _setStatus(TicketStatus s) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/tickets/${widget.ticket.id}/status', {'status': s.name});
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
      if (!mounted) return;
      final event = MessageEvent.forStatus(s);
      final shop = ref.read(shopProvider).value;
      if (event != null && shop != null && shop.ruleFor(event) != MessageRule.off && widget.user.role != Role.technician) {
        suggestMessage(context, ref, widget.ticket.id, event, shop.ruleFor(event));
      } else {
        showMessage(context, 'الجهاز بقى: ${s.label}');
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final isStaff = widget.user.role != Role.technician;
    final delivered = t.status == TicketStatus.delivered;
    final next = t.status.next;
    final scheme = Theme.of(context).colorScheme;

    final flow = TicketStatus.flow;
    // مراحل الانتظار والإلغاء بتظهر مكان المرحلة اللي هي فيها
    final currentIndex = switch (t.status) {
      TicketStatus.waitingApproval || TicketStatus.waitingParts => 1,
      TicketStatus.cancelled || TicketStatus.unrepairable => 4,
      _ => flow.indexOf(t.status),
    };

    return SectionCard(
      title: 'مراحل الصيانة',
      icon: Icons.timeline_rounded,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < flow.length; i++) ...[
                _StepDot(
                  label: i == currentIndex && !flow.contains(t.status) ? t.status.label : flow[i].label,
                  color: i == currentIndex && !flow.contains(t.status) ? statusColor(t.status) : statusColor(flow[i]),
                  done: i < currentIndex,
                  current: i == currentIndex,
                ),
                if (i < flow.length - 1)
                  Container(width: 28, height: 2, color: i < currentIndex ? scheme.primary : scheme.outlineVariant),
              ],
            ],
          ),
        ),
        if (!delivered) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (next != null)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _setStatus(next),
                  icon: Icon(statusIcon(next)),
                  label: Text('نقل لـ "${next.label}"'),
                ),
              if (isStaff && t.status.awaitingPickup || isStaff && t.status == TicketStatus.testing)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                  onPressed: _busy
                      ? null
                      : () => showDialog<void>(context: context, builder: (_) => DeliverDialog(ticket: t, user: widget.user)),
                  icon: const Icon(Icons.handshake_rounded),
                  label: const Text('تسليم للعميل'),
                ),
              if (!t.approvalPending && t.status.isOpen)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => showDialog<void>(context: context, builder: (_) => ApprovalRequestDialog(ticket: t)),
                  icon: const Icon(Icons.price_change_rounded),
                  label: const Text('طلب موافقة على تكلفة'),
                ),
              if (isStaff && t.status.awaitingPickup)
                OutlinedButton.icon(
                  onPressed: () => showDialog<void>(context: context, builder: (_) => PickupDialog(ticket: t)),
                  icon: const Icon(Icons.event_available_rounded),
                  label: Text(t.pickupAt == null ? 'معاد الاستلام' : 'تغيير معاد الاستلام'),
                ),
              MenuAnchor(
                builder: (context, controller, _) => OutlinedButton.icon(
                  onPressed: _busy ? null : () => controller.isOpen ? controller.close() : controller.open(),
                  icon: const Icon(Icons.swap_vert_rounded),
                  label: const Text('تغيير المرحلة'),
                ),
                menuChildren: [
                  for (final s in TicketStatus.values.where((s) => s != TicketStatus.delivered && s != t.status))
                    MenuItemButton(
                      leadingIcon: Icon(statusIcon(s), color: statusColor(s)),
                      onPressed: () => _setStatus(s),
                      child: Text(s.label),
                    ),
                ],
              ),
            ],
          ),
          if (isStaff && !t.status.awaitingPickup && t.status != TicketStatus.testing) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => DeliverDialog(ticket: t, user: widget.user)),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: const Text('العميل عايز ياخد الجهاز دلوقتي؟ تسليم'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.label, required this.color, required this.done, required this.current});
  final String label;
  final Color color;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = done || current;
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: current ? 34 : 28,
            height: current ? 34 : 28,
            decoration: BoxDecoration(
              color: current ? color : done ? scheme.primary : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              boxShadow: current ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)] : null,
            ),
            child: Icon(done ? Icons.check_rounded : Icons.circle, size: done ? 18 : 8, color: active ? Colors.white : scheme.outline),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(fontSize: 12, color: active ? null : scheme.onSurfaceVariant).weight(current ? FontWeight.w700 : FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends ConsumerWidget {
  const _DetailsCard({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ticket;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: MediaQuery.sizeOf(context).width < 500 ? 96 : 130, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
              Expanded(child: value),
            ],
          ),
        );
    Widget chips(List<String> items) => items.isEmpty
        ? const Text('—')
        : Wrap(spacing: 6, runSpacing: 6, children: [for (final i in items) Chip(label: Text(i), visualDensity: VisualDensity.compact)]);

    return SectionCard(
      title: 'تفاصيل الجهاز',
      icon: Icons.info_outline_rounded,
      children: [
        row('المشكلة', Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (t.problems.isNotEmpty) chips(t.problems),
            if (t.problemDesc != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(t.problemDesc!)),
          ],
        )),
        row('بيفتح؟', Text(switch (t.powersOn) { true => 'أيوه', false => 'لأ', null => 'مش معروف' })),
        row('ملاحظات الشكل', chips(t.conditionFlags)),
        if (t.conditionNotes != null) row('ملاحظات تانية', Text(t.conditionNotes!)),
        row('مع الجهاز', chips(t.accessories)),
        if (t.imei != null) row('IMEI', SelectableText(t.imei!, textDirection: TextDirection.ltr)),
        row('قفل الشاشة', Row(
          children: [
            Text(t.hasLockSecret ? t.lockType.label : 'مفيش'),
            if (t.canRevealLock) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => showDialog<void>(context: context, builder: (_) => _LockDialog(ticketId: t.id)),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: const Text('إظهار الرمز'),
              ),
            ] else if (t.hasLockSecret)
              Text('  (بيظهر للفني المسؤول بس)', style: text.bodySmall),
          ],
        )),
        if (t.createdByName != null) row('استلمه', Text(t.createdByName!)),
      ],
    );
  }
}

class _LockDialog extends ConsumerWidget {
  const _LockDialog({required this.ticketId});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(sessionProvider).value!.api!;
    return AlertDialog(
      title: const Text('رمز فتح الشاشة'),
      content: FutureBuilder(
        future: api.get('/api/tickets/$ticketId/lock'),
        builder: (context, snap) {
          if (snap.hasError) return ErrorBanner(errorText(snap.error!));
          if (!snap.hasData) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
          final type = LockType.parse(snap.data!['lockType'] as String?);
          final secret = snap.data!['secret'] as String;
          if (type == LockType.pattern) {
            return Column(mainAxisSize: MainAxisSize.min, children: [
              PatternPad(initial: PatternPad.decode(secret), onChanged: (_) {}, readOnly: true, size: 200),
              const SizedBox(height: 8),
              Text('الدايرة اللي عليها حلقة هي البداية • $secret', textDirection: TextDirection.rtl),
            ]);
          }
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Text(type.label),
            const SizedBox(height: 8),
            SelectableText(secret, textDirection: TextDirection.ltr, style: Theme.of(context).textTheme.headlineMedium?.bold),
          ]);
        },
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('قفل'))],
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.detail, required this.canEdit});
  final TicketDetail detail;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final t = detail.ticket;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget amount(String label, int cents, {Color? color, bool big = false}) => Expanded(
          child: Column(
            children: [
              Text(label, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(money(cents), style: (big ? text.titleLarge : text.titleMedium)?.bold.copyWith(color: color)),
            ],
          ),
        );

    return SectionCard(
      title: 'الحساب',
      icon: Icons.payments_rounded,
      trailing: canEdit && t.status != TicketStatus.delivered
          ? TextButton.icon(
              onPressed: () => showDialog<void>(context: context, builder: (_) => PaymentDialog(ticket: t)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('دفعة'),
            )
          : null,
      children: [
        Row(
          children: [
            amount(t.finalCents != null ? 'التكلفة النهائية' : 'التكلفة المبدئية', t.totalCents),
            amount('المدفوع', t.paidCents, color: const Color(0xFF16A34A)),
            amount('الباقي', t.remainingCents, color: t.remainingCents > 0 ? brandOrange : null, big: true),
          ],
        ),
        if (detail.payments.isNotEmpty) ...[
          const Divider(height: 24),
          for (final p in detail.payments)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                p.kind == PaymentKind.refund ? Icons.undo_rounded : Icons.arrow_downward_rounded,
                color: p.kind == PaymentKind.refund ? scheme.error : const Color(0xFF16A34A),
              ),
              title: Text('${p.kind.label} • ${p.method.label}'),
              subtitle: Text('${formatDateTime(p.createdAt)}${p.userName != null ? ' • ${p.userName}' : ''}'),
              trailing: Text(money(p.amountCents), style: const TextStyle().bold),
            ),
        ],
      ],
    );
  }
}

class _TimelineCard extends ConsumerStatefulWidget {
  const _TimelineCard({required this.detail});
  final TicketDetail detail;

  @override
  ConsumerState<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends ConsumerState<_TimelineCard> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    if (_note.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/tickets/${widget.detail.ticket.id}/notes', {'note': _note.text});
      _note.clear();
      ref.invalidate(ticketDetailProvider(widget.detail.ticket.id));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.detail.events.reversed.toList();
    final staff = ref.watch(staffProvider).value ?? const [];
    String staffName(String? id) => staff.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'فني';

    return SectionCard(
      title: 'السجل والملاحظات',
      icon: Icons.history_rounded,
      children: [
        TextField(
          controller: _note,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'اكتب ملاحظة للفنيين (العميل مش بيشوفها)',
            suffixIcon: IconButton(
              icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
              onPressed: _busy ? null : _addNote,
            ),
          ),
          onSubmitted: (_) => _addNote(),
        ),
        const SizedBox(height: 8),
        for (final e in events) _EventTile(event: e, staffName: staffName),
      ],
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.staffName});
  final TicketEvent event;
  final String Function(String?) staffName;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String title) = switch (e.type) {
      'created' => (Icons.move_to_inbox_rounded, scheme.primary, 'استلام الجهاز'),
      'status' => (
          statusIcon(TicketStatus.parse(e.to)),
          statusColor(TicketStatus.parse(e.to)),
          TicketStatus.parse(e.to).label,
        ),
      'note' => (Icons.sticky_note_2_rounded, const Color(0xFFD97706), 'ملاحظة'),
      'payment' => (Icons.payments_rounded, const Color(0xFF16A34A), 'دفعة ${money(int.tryParse(e.to ?? '') ?? 0)}'),
      'estimate' => (Icons.price_change_rounded, brandOrange, 'التكلفة المبدئية: ${money(int.tryParse(e.to ?? '') ?? 0)}'),
      'final_cost' => (Icons.price_check_rounded, brandOrange, e.to == null ? 'إلغاء التكلفة النهائية' : 'التكلفة النهائية: ${money(int.tryParse(e.to!) ?? 0)}'),
      'due' => (Icons.event_rounded, scheme.primary, e.to == null ? 'إلغاء الموعد المتوقع' : 'الموعد المتوقع: ${formatDateTime(parseDate(e.to)!)}'),
      'assign' => (Icons.engineering_rounded, const Color(0xFF7C3AED), e.to == null ? 'إلغاء تحديد الفني' : 'الفني المسؤول: ${staffName(e.to)}'),
      'approval_request' => (Icons.price_change_rounded, brandOrange, 'طلب موافقة: التكلفة الجديدة ${money(int.tryParse(e.to ?? '') ?? 0)}'),
      'approval_yes' => (Icons.thumb_up_rounded, const Color(0xFF16A34A), 'العميل وافق على ${money(int.tryParse(e.to ?? '') ?? 0)}'),
      'approval_no' => (Icons.thumb_down_rounded, scheme.error, 'العميل رفض التكلفة الجديدة'),
      'pickup' => (Icons.event_available_rounded, const Color(0xFF16A34A), e.to == null ? 'إلغاء معاد الاستلام' : 'معاد الاستلام: ${formatDateTime(parseDate(e.to)!)}'),
      'edit' => (Icons.edit_rounded, scheme.onSurfaceVariant, 'تعديل بيانات الجهاز'),
      'part' => (Icons.memory_rounded, const Color(0xFF0891B2), 'قطعة غيار: ${e.note ?? ''} × ${e.to}'),
      'part_removed' => (Icons.remove_circle_outline_rounded, scheme.onSurfaceVariant, 'شيل قطعة: ${e.note ?? ''}'),
      'warranty_return' => (Icons.verified_user_rounded, brandOrange, e.note ?? 'مرتجع ضمان'),
      _ => (Icons.bolt_rounded, scheme.onSurfaceVariant, e.type),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 15, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle().semiBold),
                if (e.note != null) Text(e.note!),
                Text(
                  '${formatDateTime(e.createdAt)}${e.userName != null ? ' • ${e.userName}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesCard extends StatelessWidget {
  const _MessagesCard({required this.messages});
  final List<SentMessage> messages;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'الرسائل للعميل',
      icon: Icons.forum_rounded,
      children: [
        for (final m in messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  m.channel == 'sms' ? Icons.sms_rounded : Icons.chat_rounded,
                  size: 20,
                  color: m.channel == 'sms' ? scheme.primary : const Color(0xFF25D366),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${MessageEvent.parse(m.event).label} • ${switch (m.status) {
                          'queued' => 'مستنية الإرسال',
                          'sending' => 'بتتبعت',
                          'sent' => 'اتبعتت ✓',
                          'failed' => 'فشلت',
                          _ => 'اتفتح واتساب',
                        }}',
                        style: TextStyle(color: m.status == 'failed' ? scheme.error : null).semiBold,
                      ),
                      Text(m.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                      if (m.error != null) Text(m.error!, style: TextStyle(color: scheme.error, fontSize: 12)),
                      Text(
                        '${formatDateTime(m.createdAt)}${m.userName != null ? ' • ${m.userName}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// كارت بيظهر لما فيه طلب موافقة مستني رد العميل.
class _ApprovalCard extends ConsumerStatefulWidget {
  const _ApprovalCard({required this.ticket, required this.isStaff});
  final Ticket ticket;
  final bool isStaff;

  @override
  ConsumerState<_ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends ConsumerState<_ApprovalCard> {
  bool _busy = false;

  Future<void> _resolve(bool approved) async {
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider).value!.api!.post('/api/tickets/${widget.ticket.id}/approval/resolve', {'approved': approved});
      ref.invalidate(ticketDetailProvider(widget.ticket.id));
      if (mounted) showMessage(context, approved ? 'اتسجلت موافقة العميل، والجهاز رجع للإصلاح' : 'اتسجل رفض العميل، والجهاز مستني يستلمه');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brandOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brandOrange.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.hourglass_top_rounded, color: brandOrange),
            const SizedBox(width: 8),
            Expanded(child: Text('مستنيين رد العميل على تكلفة زيادة', style: Theme.of(context).textTheme.titleSmall?.bold)),
          ]),
          const SizedBox(height: 8),
          Text(t.approvalNote ?? ''),
          const SizedBox(height: 4),
          Text('التكلفة الجديدة: ${money(t.approvalCents ?? 0)} (بدل ${money(t.totalCents)})', style: const TextStyle().semiBold),
          const SizedBox(height: 4),
          const Text('العميل يقدر يرد من صفحة التتبع، والرد بيوصل هنا لوحده.', style: TextStyle(fontSize: 12)),
          if (widget.isStaff) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                onPressed: _busy ? null : () => _resolve(true),
                icon: const Icon(Icons.thumb_up_rounded),
                label: const Text('العميل وافق'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _resolve(false),
                icon: const Icon(Icons.thumb_down_rounded),
                label: const Text('العميل رفض'),
              ),
              TextButton.icon(
                onPressed: () => showMessageDialog(context, t.id, MessageEvent.approval),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('ابعتله الطلب'),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
