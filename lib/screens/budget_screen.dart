import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';

const _plan = {
  BudgetCategory.needs: (label: 'Needs', pct: 0.65),
  BudgetCategory.wants: (label: 'Wants', pct: 0.15),
  BudgetCategory.savings: (label: 'Savings / Debt', pct: 0.20),
};

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(ItemKind.budget));
    final salary = ref.watch(monthlySalaryProvider);
    final query = ref.watch(searchQueryProvider(ItemKind.budget));
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
        children: const [LoadingSkeleton()],
      ),
      error: (e, _) =>
          errorState(context, () => ref.invalidate(itemsProvider(ItemKind.budget))),
      data: (all) {
        final items = filterBySearch(all, query);
        double planned(String cat) => items
            .where((i) => i.category == cat)
            .fold(0.0, (s, i) => s + (i.amount ?? 0));

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _summaryCard(context, salary, planned),
            for (final entry in _plan.entries)
              _categoryBlock(context, ref, entry.key, entry.value.label,
                  items.where((i) => i.category == entry.key).toList()),
          ],
        );
      },
    );
  }

  Widget _summaryCard(
      BuildContext context, double salary, double Function(String) planned) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly salary',
              style: TextStyle(color: c.inkSub, fontSize: 13)),
          const SizedBox(height: 2),
          Text(money(salary),
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          _stackedProportionBar(context, salary, planned),
          const SizedBox(height: 16),
          for (final e in _plan.entries)
            _planRow(context, e.value.label, e.value.pct, salary, planned(e.key)),
        ],
      ),
    );
  }

  /// At-a-glance 100%-stacked bar of actual spend share across the 3
  /// categories — a plain Row of flex segments reads just as clearly as a
  /// chart-library stacked bar for exactly 3 values, with zero added
  /// dependency weight and direct on-bar % labels (never color-only).
  Widget _stackedProportionBar(
      BuildContext context, double salary, double Function(String) planned) {
    final totals = {for (final k in _plan.keys) k: planned(k)};
    final sum = totals.values.fold(0.0, (a, b) => a + b);
    if (sum <= 0) return const SizedBox.shrink();
    final colors = {
      BudgetCategory.needs: AppColors.indigo,
      BudgetCategory.wants: AppColors.orange,
      BudgetCategory.savings: AppColors.teal,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final k in _plan.keys)
                  if (totals[k]! > 0)
                    Expanded(
                      flex: (totals[k]! * 1000 / sum).round().clamp(1, 1000),
                      child: Container(color: colors[k]),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final k in _plan.keys)
              if (totals[k]! > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: colors[k], shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      '${_plan[k]!.label} ${(totals[k]! / sum * 100).round()}%',
                      style:
                          TextStyle(fontSize: 12, color: context.colors.inkSub),
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }

  Widget _planRow(BuildContext context, String label, double pct, double salary,
      double actual) {
    final c = context.colors;
    final ideal = salary * pct;
    final over = actual > ideal;
    final ratio = ideal == 0 ? 0.0 : (actual / ideal).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$label · ${(pct * 100).round()}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              if (over) ...[
                const Icon(CupertinoIcons.arrow_up, size: 12, color: AppColors.rose),
                const SizedBox(width: 2),
              ],
              Text(
                '${money(actual)} / ${money(ideal)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: over ? AppColors.rose : c.inkSub,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: c.hair,
              valueColor: AlwaysStoppedAnimation(
                  over ? AppColors.rose : AppColors.indigo),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryBlock(BuildContext context, WidgetRef ref, String cat,
      String label, List<Item> items) {
    final total = items.fold(0.0, (s, i) => s + (i.amount ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        groupHeader(context, label, trailing: total > 0 ? money(total) : null),
        if (items.isEmpty)
          cardGroup(context, [
            _addTile(context, ref, cat, label),
          ])
        else
          cardGroup(context, [
            for (var i = 0; i < items.length; i++) ...[
              _budgetRow(context, ref, items[i]),
              if (i != items.length - 1) rowDivider(context),
            ],
            rowDivider(context),
            _addTile(context, ref, cat, label),
          ]),
      ],
    );
  }

  Widget _budgetRow(BuildContext context, WidgetRef ref, Item item) {
    return DeletableRow(
      item: item,
      semanticLabel:
          '${item.title}${item.amount != null ? ', ${money(item.amount)}' : ''}',
      child: Material(
        color: context.colors.card,
        child: InkWell(
          onTap: () =>
              showItemEditor(context, ref, ItemKind.budget, existing: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Text(item.title,
                      style: const TextStyle(fontSize: 15, height: 1.3)),
                ),
                if (item.amount != null) ...[
                  const SizedBox(width: 12),
                  Text(money(item.amount),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addTile(
      BuildContext context, WidgetRef ref, String cat, String label) {
    return Material(
      color: context.colors.card,
      child: InkWell(
        onTap: () => showItemEditor(context, ref, ItemKind.budget,
            initialCategory: cat),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              const Icon(CupertinoIcons.add_circled,
                  size: 20, color: AppColors.indigo),
              const SizedBox(width: 10),
              Text('Add to $label',
                  style: const TextStyle(
                      color: AppColors.indigo,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
