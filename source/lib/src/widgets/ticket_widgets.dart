import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/ticket_models.dart';
import '../core/ticket_status.dart';

Color statusColor(TicketStatus s) => switch (s) {
      TicketStatus.received => const Color(0xFF64748B),
      TicketStatus.diagnosing => const Color(0xFFD97706),
      TicketStatus.waitingApproval => brandOrange,
      TicketStatus.waitingParts => const Color(0xFFB45309),
      TicketStatus.repairing => const Color(0xFF7C3AED),
      TicketStatus.testing => const Color(0xFF0891B2),
      TicketStatus.ready => const Color(0xFF16A34A),
      TicketStatus.delivered => const Color(0xFF0F766E),
      TicketStatus.cancelled => const Color(0xFFDC2626),
      TicketStatus.unrepairable => const Color(0xFF991B1B),
    };

IconData statusIcon(TicketStatus s) => switch (s) {
      TicketStatus.received => Icons.move_to_inbox_rounded,
      TicketStatus.diagnosing => Icons.search_rounded,
      TicketStatus.waitingApproval => Icons.hourglass_top_rounded,
      TicketStatus.waitingParts => Icons.inventory_2_rounded,
      TicketStatus.repairing => Icons.build_rounded,
      TicketStatus.testing => Icons.fact_check_rounded,
      TicketStatus.ready => Icons.check_circle_rounded,
      TicketStatus.delivered => Icons.handshake_rounded,
      TicketStatus.cancelled => Icons.cancel_rounded,
      TicketStatus.unrepairable => Icons.block_rounded,
    };

IconData deviceIcon(String type) => switch (type) {
      'tablet' => Icons.tablet_android_rounded,
      'watch' => Icons.watch_rounded,
      'laptop' => Icons.laptop_rounded,
      'other' => Icons.devices_other_rounded,
      _ => Icons.phone_android_rounded,
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final TicketStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(status), size: dense ? 14 : 16, color: color),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(color: color, fontSize: dense ? 12 : 13).semiBold),
        ],
      ),
    );
  }
}

class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket, required this.onTap, this.showCustomer = true});

  final Ticket ticket;
  final VoidCallback onTap;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor(t.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(deviceIcon(t.deviceType), color: statusColor(t.status)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${t.number}', style: text.titleSmall?.bold.copyWith(color: scheme.primary)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(t.deviceName,
                              style: text.titleSmall?.bold, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (showCustomer)
                      Text('${t.customerName} • ${t.customerPhone}',
                          style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (t.problems.isNotEmpty)
                      Text(t.problems.join('، '), style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(t.status, dense: true),
                        if (t.overdue)
                          _Tag(icon: Icons.warning_amber_rounded, label: 'متأخر', color: scheme.error)
                        else if (t.dueAt != null && t.status.isOpen)
                          _Tag(icon: Icons.schedule_rounded, label: formatDay(t.dueAt!), color: scheme.onSurfaceVariant),
                        if (t.technicianName != null)
                          _Tag(icon: Icons.engineering_rounded, label: t.technicianName!, color: scheme.onSurfaceVariant),
                        if (t.remainingCents > 0 && t.status != TicketStatus.delivered)
                          _Tag(icon: Icons.payments_rounded, label: 'باقي ${money(t.remainingCents)}', color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      );
}

/// شاشة فاضية بأيقونة ورسالة (مثلاً: مفيش أجهزة).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
