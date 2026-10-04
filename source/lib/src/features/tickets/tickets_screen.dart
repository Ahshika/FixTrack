import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/ticket_models.dart';
import '../../core/ticket_status.dart';
import '../../widgets/common.dart';
import '../../widgets/ticket_widgets.dart';
import 'intake_screen.dart';
import 'providers.dart';
import 'ticket_detail_screen.dart';

const ticketScopes = <String, String>{
  'active': 'كل اللي في المحل',
  'open': 'تحت الشغل',
  'overdue': 'متأخر',
  'pickup': 'مستني الاستلام',
  'pickupToday': 'استلامات النهارده',
  'waitingParts': 'مستني قطع غيار',
  'delivered': 'اتسلم',
  'all': 'الكل',
};

Future<void> openTicket(BuildContext context, String id) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TicketDetailScreen(ticketId: id)));

Future<void> openIntake(BuildContext context) async {
  final id = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const IntakeScreen()));
  if (id != null && context.mounted) await openTicket(context, id);
}

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key, this.initialScope = 'active', this.standalone = false});

  final String initialScope;

  /// لو الشاشة مفتوحة لوحدها (مش تاب في الشاشة الرئيسية) بيظهر زرار رجوع.
  final bool standalone;

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  late String _scope = widget.initialScope;
  String _query = '';
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => _query = v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).value!.user!;
    final canIntake = user.role != Role.technician;
    // لو فيه بحث، بندوّر في كل الأجهزة مش في الفلتر الحالي بس
    final query = (scope: _query.isNotEmpty ? 'all' : _scope, q: _query);
    final tickets = ref.watch(ticketsProvider(query));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: Text(user.role == Role.technician ? 'الأجهزة اللي عليا' : 'الأجهزة'),
      ),
      floatingActionButton: canIntake
          ? FloatingActionButton.extended(
              onPressed: () => openIntake(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('استلام جهاز'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'دوّر برقم الوصل، أو اسم العميل، أو التليفون، أو الموديل، أو IMEI',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          if (_query.isEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final e in ticketScopes.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _scope == e.key,
                        onSelected: (_) => setState(() => _scope = e.key),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: tickets.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e))),
              ),
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: _query.isNotEmpty ? Icons.search_off_rounded : Icons.inbox_rounded,
                      message: _query.isNotEmpty
                          ? 'مفيش نتايج لـ "$_query"'
                          : _scope == 'active' && canIntake
                              ? 'مفيش أجهزة في المحل دلوقتي.\nدوس "استلام جهاز" عشان تسجل أول جهاز.'
                              : 'مفيش أجهزة هنا',
                    )
                  : RefreshIndicator(
                      onRefresh: () => ref.refresh(ticketsProvider(query).future),
                      child: _TicketList(tickets: list),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList({required this.tickets});
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 1100 ? 3 : c.maxWidth >= 720 ? 2 : 1;
      if (columns == 1) {
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          itemCount: tickets.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) => TicketCard(ticket: tickets[i], onTap: () => openTicket(context, tickets[i].id)),
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 142,
        ),
        itemCount: tickets.length,
        itemBuilder: (context, i) => TicketCard(ticket: tickets[i], onTap: () => openTicket(context, tickets[i].id)),
      );
    });
  }
}

/// زرار صغير بيعرض مرحلة معينة (بيستخدم في الفلاتر).
String scopeLabel(String scope) => ticketScopes[scope] ?? TicketStatus.parse(scope).label;
