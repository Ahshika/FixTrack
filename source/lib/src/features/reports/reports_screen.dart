import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/form_fields.dart';
import '../tickets/providers.dart';
import 'report_export.dart';

typedef ReportRange = ({DateTime from, DateTime to, String label});

final reportProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, ({String from, String to})>((ref, r) async {
  return apiOf(ref).get('/api/reports/summary', query: {'from': r.from, 'to': r.to});
});

List<ReportRange> _presets() {
  final n = DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final weekStart = today.subtract(Duration(days: (today.weekday + 1) % 7)); // الأسبوع بيبدأ السبت
  return [
    (from: today, to: today.add(const Duration(days: 1)), label: 'النهارده'),
    (from: today.subtract(const Duration(days: 1)), to: today, label: 'امبارح'),
    (from: weekStart, to: today.add(const Duration(days: 1)), label: 'الأسبوع ده'),
    (from: DateTime(n.year, n.month), to: today.add(const Duration(days: 1)), label: 'الشهر ده'),
    (from: DateTime(n.year, n.month - 1), to: DateTime(n.year, n.month), label: 'الشهر اللي فات'),
    (from: DateTime(n.year), to: today.add(const Duration(days: 1)), label: 'السنة دي'),
  ];
}

/// التقارير (لصاحب المحل): الربح، والمبيعات، والصيانة، والفنيين، والمصروفات، والمخزون، والديون.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late ReportRange _range = _presets()[3];

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _range.from, end: _range.to.subtract(const Duration(days: 1))),
    );
    if (r == null) return;
    setState(() => _range = (
          from: r.start,
          to: DateTime(r.end.year, r.end.month, r.end.day + 1),
          label: '${formatDate(r.start)} ← ${formatDate(r.end)}',
        ));
  }

  @override
  Widget build(BuildContext context) {
    final key = (from: _range.from.toUtc().toIso8601String(), to: _range.to.toUtc().toIso8601String());
    final data = ref.watch(reportProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير'),
        actions: [
          if (data.hasValue) ...[
            TextButton.icon(
              onPressed: () => exportReportExcel(context, data.value!, _range.label),
              icon: const Icon(Icons.table_view_rounded),
              label: const Text('Excel'),
            ),
            TextButton.icon(
              onPressed: () => exportReportPdf(context, ref, data.value!, _range.label),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('PDF'),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final p in _presets())
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(label: Text(p.label), selected: _range.label == p.label, onSelected: (_) => setState(() => _range = p)),
              ),
            ActionChip(avatar: const Icon(Icons.date_range_rounded, size: 18), label: const Text('فترة تانية'), onPressed: _pickCustom),
          ]),
        ),
        Expanded(
          child: data.when(
            skipLoadingOnReload: true,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(20), child: ErrorBanner(errorText(e)))),
            data: (r) => _ReportBody(report: r, label: _range.label),
          ),
        ),
      ]),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report, required this.label});
  final Map<String, dynamic> report;
  final String label;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final sales = r['sales'] as Map<String, dynamic>;
    final repairs = r['repairs'] as Map<String, dynamic>;
    final services = r['services'] as Map<String, dynamic>;
    final expenses = r['expenses'] as Map<String, dynamic>;
    final stock = r['stock'] as Map<String, dynamic>;
    final receivables = r['receivables'] as Map<String, dynamic>;
    final payables = r['payables'] as Map<String, dynamic>;
    final techs = (r['technicians'] as List).cast<Map<String, dynamic>>();
    final net = r['netProfitCents'] as int;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      // الرقم الأهم لوحده
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('صافي الربح • $label', style: TextStyle(color: scheme.onSurfaceVariant)),
            Text(money(net), style: text.displaySmall?.bold.copyWith(color: net >= 0 ? scheme.onSurface : scheme.error)),
            Text('ربح المبيعات + ربح الصيانة + عمولات المحافظ − المصروفات', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : 2;
        final w = (c.maxWidth - (cols - 1) * 12) / cols;
        Widget tile(String title, int cents, String sub) => SizedBox(
              width: w,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: text.bodySmall),
                    Text(money(cents), style: text.titleLarge?.bold),
                    Text(sub, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant), maxLines: 2),
                  ]),
                ),
              ),
            );
        return Wrap(spacing: 12, runSpacing: 12, children: [
          tile('المبيعات', sales['revenueCents'] as int, '${sales['count']} فاتورة • ربح ${money(sales['profitCents'] as int)}'),
          tile('الصيانة', repairs['revenueCents'] as int, '${repairs['delivered']} جهاز اتسلم • ربح ${money(repairs['profitCents'] as int)}'),
          tile('عمولات المحافظ', services['commissionCents'] as int, '${(services['byWallet'] as List).fold<int>(0, (s, w) => s + (w['count'] as int))} عملية'),
          tile('المصروفات', expenses['totalCents'] as int, '${(expenses['byCategory'] as List).length} بند'),
        ]);
      }),
      const SizedBox(height: 12),
      SectionCard(title: 'الدخل يوم بيوم (مبيعات + صيانة)', icon: Icons.bar_chart_rounded, children: [
        _DailyBars(days: (r['daily'] as List).cast<Map<String, dynamic>>()),
      ]),
      const SizedBox(height: 12),
      _TableCard(
        title: 'أكتر الأصناف مبيعاً',
        icon: Icons.local_mall_rounded,
        headers: const ['الصنف', 'الكمية', 'المبيعات', 'الربح'],
        rows: [
          for (final p in (sales['topProducts'] as List).cast<Map<String, dynamic>>())
            [p['name'] as String, '${p['qty']}', money(p['revenue'] as int), money(p['profit'] as int)],
        ],
        empty: 'مفيش مبيعات في الفترة دي',
      ),
      const SizedBox(height: 12),
      _TableCard(
        title: 'الفنيين',
        icon: Icons.engineering_rounded,
        headers: const ['الفني', 'أجهزة', 'ربح الصيانة', 'العمولة', 'مرتجع ضمان', 'متوسط الوقت'],
        rows: [
          for (final t in techs)
            [
              t['name'] as String,
              '${t['delivered']}',
              money(t['laborCents'] as int),
              t['commissionType'] == 'none' ? '—' : money(t['commissionCents'] as int),
              '${t['warrantyReturns']}',
              '${t['avgHours']} ساعة',
            ],
        ],
        empty: 'مفيش أجهزة اتسلمت في الفترة دي',
      ),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final two = c.maxWidth >= 800;
        final problems = _TableCard(
          title: 'أكتر الأعطال',
          icon: Icons.report_problem_rounded,
          headers: const ['العطل', 'مرات'],
          rows: [for (final p in (repairs['topProblems'] as List).cast<Map<String, dynamic>>()) [p['name'] as String, '${p['count']}']],
          empty: '—',
        );
        final models = _TableCard(
          title: 'أكتر الموديلات في الصيانة',
          icon: Icons.phone_android_rounded,
          headers: const ['الموديل', 'مرات'],
          rows: [for (final p in (repairs['topModels'] as List).cast<Map<String, dynamic>>()) [p['name'] as String, '${p['count']}']],
          empty: '—',
        );
        return two
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: problems), const SizedBox(width: 12), Expanded(child: models)])
            : Column(children: [problems, const SizedBox(height: 12), models]);
      }),
      const SizedBox(height: 12),
      _TableCard(
        title: 'المصروفات',
        icon: Icons.money_off_rounded,
        headers: const ['البند', 'المبلغ'],
        rows: [for (final e in (expenses['byCategory'] as List).cast<Map<String, dynamic>>()) [e['name'] as String, money(e['total'] as int)]],
        empty: 'مفيش مصروفات',
      ),
      const SizedBox(height: 12),
      _TableCard(
        title: 'عمولات المحافظ',
        icon: Icons.account_balance_rounded,
        headers: const ['المحفظة', 'عمليات', 'العمولة'],
        rows: [for (final w in (services['byWallet'] as List).cast<Map<String, dynamic>>()) [w['name'] as String, '${w['count']}', money(w['commission'] as int)]],
        empty: 'مفيش عمليات',
      ),
      const SectionTitle('دلوقتي'),
      _TableCard(
        title: 'فلوس ليك برا (ديون العملاء): ${money(receivables['totalCents'] as int)}',
        icon: Icons.call_received_rounded,
        headers: const ['العميل', 'التليفون', 'عليه'],
        rows: [
          for (final c in (receivables['customers'] as List).cast<Map<String, dynamic>>())
            [c['name'] as String, c['phone'] as String? ?? '', money(c['balanceCents'] as int)],
        ],
        empty: 'مفيش ديون على العملاء',
      ),
      const SizedBox(height: 12),
      _TableCard(
        title: 'فلوس عليك للموردين: ${money(payables['totalCents'] as int)}',
        icon: Icons.call_made_rounded,
        headers: const ['المورد', 'ليه'],
        rows: [for (final s in (payables['suppliers'] as List).cast<Map<String, dynamic>>()) [s['name'] as String, money(s['balanceCents'] as int)]],
        empty: 'مفيش فلوس عليك للموردين',
      ),
      const SizedBox(height: 12),
      _TableCard(
        title: 'بضاعة واقفة (ما اتباعتش من 60 يوم) • قيمة المخزون كله ${money(stock['valueCents'] as int)}',
        icon: Icons.inventory_rounded,
        headers: const ['الصنف', 'الكمية', 'قيمتها'],
        rows: [for (final d in (stock['deadStock'] as List).cast<Map<String, dynamic>>()) [d['name'] as String, '${d['qty']}', money(d['value'] as int)]],
        empty: 'مفيش بضاعة واقفة 👍',
      ),
    ]);
  }
}

/// رسم أعمدة بسيط لمجموعة واحدة (الدخل اليومي): أعمدة رفيعة بحواف مدورة، وخطوط خلفية هادية، والقيمة بتظهر بالضغط أو بالماوس.
class _DailyBars extends StatefulWidget {
  const _DailyBars({required this.days});
  final List<Map<String, dynamic>> days;

  @override
  State<_DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<_DailyBars> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final scheme = Theme.of(context).colorScheme;
    if (days.isEmpty) return Padding(padding: const EdgeInsets.all(20), child: Text('مفيش دخل في الفترة دي', style: TextStyle(color: scheme.onSurfaceVariant)));
    final values = [for (final d in days) (d['sales'] as int? ?? 0) + (d['repairs'] as int? ?? 0)];
    final maxV = values.fold<int>(1, (m, v) => v > m ? v : m);
    final h = _hover;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 22,
        child: Text(
          h == null
              ? 'أعلى يوم: ${money(maxV)}'
              : '${formatDay(DateTime.parse(days[h]['date'] as String))}: ${money(values[h])} (مبيعات ${money(days[h]['sales'] as int? ?? 0)} • صيانة ${money(days[h]['repairs'] as int? ?? 0)})',
          style: const TextStyle(fontSize: 13).semiBold,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 180,
        child: Directionality(
          // الوقت بيمشي من الشمال لليمين في الرسم حتى في البرنامج العربي
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(builder: (context, c) {
            final slot = c.maxWidth / values.length;
            final barW = (slot - 2).clamp(2.0, 28.0);
            return Stack(children: [
              for (final f in const [0.25, 0.5, 0.75, 1.0])
                Positioned(left: 0, right: 0, bottom: 180 * f - 1, child: Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5))),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < values.length; i++)
                  MouseRegion(
                    onEnter: (_) => setState(() => _hover = i),
                    onExit: (_) => setState(() => _hover = null),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _hover = _hover == i ? null : i),
                      child: SizedBox(
                        width: slot,
                        height: 180,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: barW,
                            height: values[i] == 0 ? 0 : (170 * values[i] / maxV).clamp(3.0, 170.0),
                            decoration: BoxDecoration(
                              color: h == null || h == i ? brandBlue : brandBlue.withValues(alpha: 0.35),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
      const SizedBox(height: 4),
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_short(days.first['date'] as String), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          if (days.length > 1) Text(_short(days.last['date'] as String), style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ]),
      ),
    ]);
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.title, required this.icon, required this.headers, required this.rows, required this.empty});
  final String title;
  final IconData icon;
  final List<String> headers;
  final List<List<String>> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(title: title, icon: icon, children: [
      if (rows.isEmpty)
        Text(empty, style: TextStyle(color: scheme.onSurfaceVariant))
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 44,
            columnSpacing: 24,
            headingTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13).semiBold,
            columns: [for (final h in headers) DataColumn(label: Text(h))],
            rows: [for (final r in rows) DataRow(cells: [for (final c in r) DataCell(Text(c))])],
          ),
        ),
    ]);
  }
}

/// "2026-09-01" ← "1/9"
String _short(String isoDate) {
  final d = DateTime.parse(isoDate);
  return '${d.day}/${d.month}';
}
