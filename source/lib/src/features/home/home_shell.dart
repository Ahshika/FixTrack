import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../branches/branches_screen.dart';
import '../customers/customers_screen.dart';
import '../inventory/products_screen.dart';
import '../messages/sms_gateway.dart';
import '../phones/phones_screen.dart';
import '../pos/cash_screen.dart';
import '../pos/pos_screen.dart';
import '../pos/sales_screen.dart';
import '../purchases/purchases_screen.dart';
import '../reports/reports_screen.dart';
import '../services/services_screen.dart';
import '../settings/settings_screen.dart';
import '../tickets/tickets_screen.dart';
import '../users/users_screen.dart';
import 'dashboard_screen.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.builder, {this.roles});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;

  /// لو null يبقى متاح لكل الصلاحيات.
  final Set<Role>? roles;
}

const _staff = {Role.owner, Role.reception};

final _destinations = <_Destination>[
  _Destination('الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, () => const DashboardScreen()),
  _Destination('الكاشير', Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, () => const PosScreen(), roles: _staff),
  _Destination('الصيانة', Icons.phone_android_outlined, Icons.phone_android_rounded, () => const TicketsScreen()),
  _Destination('المخزون', Icons.inventory_2_outlined, Icons.inventory_2_rounded, () => const ProductsScreen(), roles: _staff),
  _Destination('الفواتير', Icons.receipt_long_outlined, Icons.receipt_long_rounded, () => const SalesScreen(), roles: _staff),
  _Destination('الموبايلات', Icons.phone_iphone_outlined, Icons.phone_iphone_rounded, () => const PhonesScreen(), roles: _staff),
  _Destination('المحافظ', Icons.account_balance_outlined, Icons.account_balance_rounded, () => const ServicesScreen(), roles: _staff),
  _Destination('المشتريات', Icons.local_shipping_outlined, Icons.local_shipping_rounded, () => const PurchasesScreen(), roles: _staff),
  _Destination('الخزنة', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, () => const CashScreen(), roles: _staff),
  _Destination('العملاء', Icons.people_outline_rounded, Icons.people_rounded, () => const CustomersScreen(), roles: _staff),
  _Destination('الفروع', Icons.hub_outlined, Icons.hub_rounded, () => const BranchesScreen(), roles: _staff),
  _Destination('التقارير', Icons.insights_outlined, Icons.insights_rounded, () => const ReportsScreen(), roles: {Role.owner}),
  _Destination('الموظفين', Icons.badge_outlined, Icons.badge_rounded, () => const UsersScreen(), roles: {Role.owner}),
  _Destination('الإعدادات', Icons.settings_outlined, Icons.settings_rounded, () => const SettingsScreen()),
];

/// الهيكل الأساسي بعد الدخول: قائمة جانبية على الشاشات الكبيرة، وشريط تحت على الموبايل.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).value!.user!;
    // بوابة الـ SMS (لو متفعّلة على الموبايل ده) بتشتغل طول ما البرنامج مفتوح
    ref.watch(smsGatewayProvider);
    final items = _destinations.where((d) => d.roles == null || d.roles!.contains(user.role)).toList();
    final index = _index.clamp(0, items.length - 1);
    final page = KeyedSubtree(key: ValueKey(items[index].label), child: items[index].builder());
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (!wide) {
      // الموبايل بيشيل 5 أزرار بالكتير تحت؛ الباقي في "المزيد"
      final primary = items.length <= 5 ? items : items.take(4).toList();
      final more = items.length <= 5 ? const <_Destination>[] : items.skip(4).toList();
      final inMore = index >= primary.length;
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: inMore ? primary.length : index,
          onDestinationSelected: (i) async {
            if (i < primary.length) return setState(() => _index = i);
            final picked = await showModalBottomSheet<int>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var k = 0; k < more.length; k++)
                    ListTile(
                      leading: Icon(more[k].icon),
                      title: Text(more[k].label),
                      selected: index == primary.length + k,
                      onTap: () => Navigator.pop(context, primary.length + k),
                    ),
                ]),
              ),
            );
            if (picked != null) setState(() => _index = picked);
          },
          destinations: [
            for (final d in primary) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
            if (more.isNotEmpty)
              NavigationDestination(
                icon: const Icon(Icons.more_horiz_rounded),
                label: inMore ? items[index].label : 'المزيد',
              ),
          ],
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          Material(
            color: scheme.surfaceContainerLowest,
            child: SizedBox(
              width: 240,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 20),
                      child: Row(children: [FixTrackLogo(size: 36, showName: false), SizedBox(width: 10), _BrandName()]),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                              child: ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(vertical: -1),
                                selected: i == index,
                                selectedTileColor: scheme.primaryContainer,
                                selectedColor: scheme.onPrimaryContainer,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                leading: Icon(i == index ? items[i].selectedIcon : items[i].icon),
                                title: Text(items[i].label, style: (i == index ? const TextStyle().semiBold : const TextStyle()).copyWith(fontSize: 15)),
                                onTap: () => setState(() => _index = i),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _UserFooter(user: user),
                  ],
                ),
              ),
            ),
          ),
          VerticalDivider(width: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _BrandName extends StatelessWidget {
  const _BrandName();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Fix',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const TextSpan(
              text: 'Track',
              style: TextStyle(color: brandOrange),
            ),
          ],
        ),
        style: Theme.of(context).textTheme.titleLarge?.bold,
      ),
    );
  }
}

class _UserFooter extends ConsumerWidget {
  const _UserFooter({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Text(user.name.characters.first, style: TextStyle(color: scheme.onSecondaryContainer)),
        ),
        title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(user.role.label),
        trailing: IconButton(
          tooltip: 'خروج',
          icon: const Icon(Icons.logout_rounded),
          onPressed: () => ref.read(sessionProvider.notifier).logout(),
        ),
      ),
    );
  }
}
