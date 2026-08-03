import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';

/// Dena Paona ledger — who owes whom.
class DealingsScreen extends ConsumerWidget {
  const DealingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(ItemKind.deal));
    final query = ref.watch(searchQueryProvider(ItemKind.deal));
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
        children: const [LoadingSkeleton()],
      ),
      error: (e, _) =>
          errorState(context, () => ref.invalidate(itemsProvider(ItemKind.deal))),
      data: (all) {
        final items = filterBySearch(all, query);
        if (items.isEmpty) {
          return emptyState(
            CupertinoIcons.arrow_right_arrow_left,
            'No dealings',
            'Track money you owe and money owed to you.',
            onAction: () => showItemEditor(context, ref, ItemKind.deal),
            actionLabel: 'Add a dealing',
          );
        }
        final iOwe = items
            .where((i) => i.direction == DealDirection.iOweThem)
            .toList();
        final theyOwe = items
            .where((i) => i.direction == DealDirection.theyOweMe)
            .toList();
        final other = items.where((i) => i.direction == null).toList();
        final oweTotal = _sum(iOwe);
        final owedTotal = _sum(theyOwe);

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _balanceCard(context, items, oweTotal, owedTotal),
            if (iOwe.isNotEmpty) ...[
              groupHeader(context, 'I owe', trailing: money(oweTotal)),
              cardGroup(context, _rows(context, ref, iOwe)),
            ],
            if (theyOwe.isNotEmpty) ...[
              groupHeader(context, 'Owed to me', trailing: money(owedTotal)),
              cardGroup(context, _rows(context, ref, theyOwe)),
            ],
            if (other.isNotEmpty) ...[
              groupHeader(context, 'Notes & assets'),
              cardGroup(context, _rows(context, ref, other)),
            ],
          ],
        );
      },
    );
  }

  double _sum(List<Item> l) => l.fold(0.0, (s, i) => s + (i.amount ?? 0));

  Widget _balanceCard(
      BuildContext context, List<Item> items, double owe, double owed) {
    final net = owed - owe;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showWaterfall(context, items),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(18),
        decoration: cardDecoration(context),
        child: Column(
          children: [
            Row(
              children: [
                _stat('I owe', owe, AppColors.rose),
                Container(width: 1, height: 40, color: context.colors.hair),
                _stat('Owed to me', owed, AppColors.teal),
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
                    ? 'Net position: +${money(net)}'
                    : 'Net position: −${money(net.abs())}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: net >= 0 ? AppColors.teal : AppColors.rose,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Tap for breakdown',
                style: TextStyle(fontSize: 12, color: context.colors.inkSub)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double v, Color c) {
    return Expanded(
      child: Builder(builder: (context) {
        return Column(
          children: [
            Text(label,
                style: TextStyle(color: context.colors.inkSub, fontSize: 13)),
            const SizedBox(height: 4),
            Text(money(v),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: c)),
          ],
        );
      }),
    );
  }

  List<Widget> _rows(BuildContext context, WidgetRef ref, List<Item> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(_row(context, ref, items[i]));
      if (i != items.length - 1) out.add(rowDivider(context));
    }
    return out;
  }

  Widget _row(BuildContext context, WidgetRef ref, Item item) {
    final owe = item.direction == DealDirection.iOweThem;
    final color = item.direction == null
        ? context.colors.inkSub
        : (owe ? AppColors.rose : AppColors.teal);
    return DeletableRow(
      item: item,
      semanticLabel:
          '${item.title}${item.amount != null ? ', ${owe ? 'I owe' : 'owed to me'} ${money(item.amount)}' : ''}',
      child: Material(
        color: context.colors.card,
        child: InkWell(
          onTap: () =>
              showItemEditor(context, ref, ItemKind.deal, existing: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style:
                              const TextStyle(fontSize: 15, height: 1.3)),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(item.note,
                            style: TextStyle(
                                fontSize: 13, color: context.colors.inkSub)),
                      ],
                    ],
                  ),
                ),
                if (item.amount != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    '${owe ? '−' : '+'}${moneyK(item.amount)}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showWaterfall(BuildContext context, List<Item> items) {
    final withAmount =
        items.where((i) => i.amount != null && i.direction != null).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _WaterfallSheet(items: withAmount),
    );
  }
}

/// Running-total waterfall: each entry as a floating bar from the previous
/// total to the new one, plus a final "Net" bar from zero — the mental model
/// this ledger already uses ("who owes whom, cumulatively"), just visualised.
class _WaterfallSheet extends StatelessWidget {
  const _WaterfallSheet({required this.items});
  final List<Item> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    var running = 0.0;
    final bars = <BarChartGroupData>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final signed = item.direction == DealDirection.iOweThem
          ? -(item.amount ?? 0)
          : (item.amount ?? 0);
      final from = running;
      running += signed;
      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          fromY: signed >= 0 ? from : running,
          toY: signed >= 0 ? running : from,
          color: signed >= 0 ? AppColors.teal : AppColors.rose,
          width: 14,
          borderRadius: BorderRadius.circular(3),
        ),
      ]));
    }
    bars.add(BarChartGroupData(x: items.length, barRods: [
      BarChartRodData(
        fromY: 0,
        toY: running,
        color: AppColors.indigo,
        width: 14,
        borderRadius: BorderRadius.circular(3),
      ),
    ]));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Net position breakdown',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 4),
            Text(
              'Each bar is one dealing; the last (indigo) bar is the running net.',
              style: TextStyle(fontSize: 13, color: c.inkSub),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: items.isEmpty
                  ? Center(
                      child: Text('No amounts to chart',
                          style: TextStyle(color: c.inkSub)))
                  : BarChart(BarChartData(
                      barGroups: bars,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(
                        show: true,
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                    )),
            ),
            const SizedBox(height: 8),
            // Accessible fallback — the chart is supplementary, this list is
            // the primary reading (per ui-ux-pro-max: never chart-only).
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      items[i].direction == DealDirection.iOweThem
                          ? CupertinoIcons.arrow_down
                          : CupertinoIcons.arrow_up,
                      size: 12,
                      color: items[i].direction == DealDirection.iOweThem
                          ? AppColors.rose
                          : AppColors.teal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(items[i].title, style: const TextStyle(fontSize: 13))),
                    Text(money(items[i].amount), style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
