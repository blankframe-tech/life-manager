import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../util/week.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';

final _rowDate = DateFormat('EEE, d MMM');

/// How many weeks the trend sheet looks back over.
const _kTrendWeeks = 8;

/// A plain log of money in and money out, grouped into weeks.
///
/// Deliberately separate from Budget (a *plan* for the month) and Dealings (who
/// owes whom): this one only records what actually moved, tagged with a
/// category the user defines in Settings → Transactions.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(ItemKind.txn));
    final query = ref.watch(searchQueryProvider(ItemKind.txn));
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
        children: const [LoadingSkeleton()],
      ),
      error: (e, _) =>
          errorState(context, () => ref.invalidate(itemsProvider(ItemKind.txn))),
      data: (all) {
        if (all.isEmpty) {
          return emptyState(
            CupertinoIcons.creditcard,
            'No transactions',
            'Log what you spend and earn, and see it add up by week.',
            onAction: () => showItemEditor(context, ref, ItemKind.txn),
            actionLabel: 'Add a transaction',
          );
        }
        final items = _search(all, query);
        if (items.isEmpty) {
          return emptyState(
            CupertinoIcons.search,
            'No matches',
            'Nothing here matches "${query.trim()}".',
          );
        }

        final weeks = rollupByWeek(items);
        final thisWeekStart = startOfWeek(DateTime.now());
        final current = weeks.firstWhere((w) => w.start == thisWeekStart,
            orElse: () => WeekRollup.empty(thisWeekStart));

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _summaryCard(context, current, weeks),
            for (final week in weeks) ..._weekBlock(context, ref, week),
          ],
        );
      },
    );
  }

  /// Search also matches the category, which is the thing you actually want to
  /// pull up here ("food") and isn't part of the shared title/note filter.
  List<Item> _search(List<Item> items, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return items
        .where((i) =>
            i.title.toLowerCase().contains(q) ||
            i.note.toLowerCase().contains(q) ||
            (i.category ?? '').toLowerCase().contains(q))
        .toList();
  }

  Widget _summaryCard(
      BuildContext context, WeekRollup week, List<WeekRollup> weeks) {
    final c = context.colors;
    final net = week.net;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => _TrendSheet(weeks: weeks),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(18),
        decoration: cardDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('This week',
                      style: TextStyle(
                          color: c.inkSub,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3)),
                ),
                Text(weekRangeLabel(week.start),
                    style: TextStyle(color: c.inkSub, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stat(context, 'Earned', week.earned, AppColors.teal),
                Container(width: 1, height: 40, color: c.hair),
                _stat(context, 'Spent', week.spent, AppColors.rose),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: (net >= 0 ? AppColors.teal : AppColors.rose)
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                net >= 0
                    ? 'Left over: +${money(net)}'
                    : 'Overspent: −${money(net.abs())}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: net >= 0 ? AppColors.teal : AppColors.rose,
                ),
              ),
            ),
            if (week.spendByCategory.isNotEmpty) ...[
              const SizedBox(height: 16),
              categoryBar(context, week.spendByCategory),
            ],
            const SizedBox(height: 10),
            Text('Tap for the last $_kTrendWeeks weeks',
                style: TextStyle(fontSize: 12, color: c.inkSub)),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, double value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(color: context.colors.inkSub, fontSize: 13)),
          const SizedBox(height: 4),
          Text(money(value),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  List<Widget> _weekBlock(
      BuildContext context, WidgetRef ref, WeekRollup week) {
    final net = week.net;
    return [
      groupHeader(context, weekLabel(week.start),
          trailing: net >= 0 ? '+${money(net)}' : '−${money(net.abs())}'),
      cardGroup(context, [
        _weekTotalsRow(context, week),
        rowDivider(context),
        for (var i = 0; i < week.items.length; i++) ...[
          _row(context, ref, week.items[i]),
          if (i != week.items.length - 1) rowDivider(context),
        ],
      ]),
    ];
  }

  /// The week's rollup line: in, out, and where the spending went.
  Widget _weekTotalsRow(BuildContext context, WeekRollup week) {
    final c = context.colors;
    final byCategory = week.spendByCategory;
    return Container(
      color: c.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('In ${money(week.earned)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.teal)),
              Text('  ·  ', style: TextStyle(fontSize: 13, color: c.inkSub)),
              Text('Out ${money(week.spent)}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.rose)),
              const Spacer(),
              Text('${week.items.length} entries',
                  style: TextStyle(fontSize: 12, color: c.inkSub)),
            ],
          ),
          if (byCategory.isNotEmpty) ...[
            const SizedBox(height: 10),
            categoryBar(context, byCategory),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Item item) {
    final c = context.colors;
    final earn = item.isEarning;
    final category = item.category ?? 'Uncategorised';
    final detail = [
      _rowDate.format(item.occurredAt),
      if (item.note.isNotEmpty) item.note,
    ].join(' · ');
    return DeletableRow(
      item: item,
      semanticLabel: '${item.title}, $category, '
          '${earn ? 'earned' : 'spent'} ${money(item.amount)}, '
          '${_rowDate.format(item.occurredAt)}',
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: () =>
              showItemEditor(context, ref, ItemKind.txn, existing: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: categoryColor(category),
                        shape: BoxShape.circle),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(fontSize: 15, height: 1.3)),
                      const SizedBox(height: 3),
                      Text('$category · $detail',
                          style: TextStyle(fontSize: 12, color: c.inkSub)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${earn ? '+' : '−'}${money(item.amount)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: earn ? AppColors.teal : c.ink,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 100%-stacked bar of spending per category, with a labelled legend — the
/// same device the Budget screen uses for its three buckets, generalised to
/// however many categories exist. Never colour-only: every segment is named
/// with its share in the legend below.
Widget categoryBar(BuildContext context, Map<String, double> byCategory,
    {int max = 5}) {
  final total = byCategory.values.fold(0.0, (a, b) => a + b);
  if (total <= 0) return const SizedBox.shrink();

  // Long tails make both the bar and the legend unreadable, so everything past
  // the top few collapses into one grey "Other" slice.
  final entries = byCategory.entries.toList();
  final shown = entries.take(max).toList();
  final otherTotal =
      entries.skip(max).fold(0.0, (sum, e) => sum + e.value);
  final segments = <(String, double, Color)>[
    for (final e in shown) (e.key, e.value, categoryColor(e.key)),
    if (otherTotal > 0) ('Other', otherTotal, context.colors.inkSub),
  ];

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          child: Row(
            children: [
              for (final (_, value, color) in segments)
                Expanded(
                  flex: (value * 1000 / total).round().clamp(1, 1000),
                  child: Container(color: color),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final (label, value, color) in segments)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('$label ${(value / total * 100).round()}%',
                    style: TextStyle(
                        fontSize: 12, color: context.colors.inkSub)),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Earned vs spent for the last [_kTrendWeeks] weeks, so a bad week is visible
/// as a shape and not just a number.
class _TrendSheet extends StatelessWidget {
  const _TrendSheet({required this.weeks});

  final List<WeekRollup> weeks;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Oldest → newest, so the chart reads left to right like a timeline.
    final recent = weeks.take(_kTrendWeeks).toList().reversed.toList();
    final peak = recent.fold(
        0.0, (m, w) => [m, w.earned, w.spent].reduce((a, b) => a > b ? a : b));

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Weekly trend',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              'Earned (teal) against spent (rose), most recent week on the right.',
              style: TextStyle(fontSize: 13, color: c.inkSub),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(BarChartData(
                maxY: peak == 0 ? 1 : peak * 1.15,
                barGroups: [
                  for (var i = 0; i < recent.length; i++)
                    BarChartGroupData(x: i, barsSpace: 3, barRods: [
                      BarChartRodData(
                        toY: recent[i].earned,
                        color: AppColors.teal,
                        width: 9,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      BarChartRodData(
                        toY: recent[i].spent,
                        color: AppColors.rose,
                        width: 9,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ]),
                ],
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  show: true,
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= recent.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('d/M').format(recent[i].start),
                            style: TextStyle(fontSize: 10, color: c.inkSub),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(height: 12),
            // The chart is supplementary; this list is the primary reading.
            for (final week in recent.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(weekLabel(week.start),
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Text('+${money(week.earned)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.teal)),
                    const SizedBox(width: 10),
                    Text('−${money(week.spent)}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.rose)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 74,
                      child: Text(
                        week.net >= 0
                            ? '+${money(week.net)}'
                            : '−${money(week.net.abs())}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
