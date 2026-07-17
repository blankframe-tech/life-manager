import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';

/// Monthly take-home used for the 65/20/15 ideal split.
const kMonthlySalary = 40000.0;

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
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        double planned(String cat) => items
            .where((i) => i.category == cat)
            .fold(0.0, (s, i) => s + (i.amount ?? 0));

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _summaryCard(planned),
            for (final entry in _plan.entries)
              _categoryBlock(context, ref, entry.key, entry.value.label,
                  items.where((i) => i.category == entry.key).toList()),
          ],
        );
      },
    );
  }

  Widget _summaryCard(double Function(String) planned) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly salary',
              style: TextStyle(color: AppColors.inkSub, fontSize: 13)),
          const SizedBox(height: 2),
          Text(money(kMonthlySalary),
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          for (final e in _plan.entries)
            _planRow(e.value.label, e.value.pct, planned(e.key)),
        ],
      ),
    );
  }

  Widget _planRow(String label, double pct, double actual) {
    final ideal = kMonthlySalary * pct;
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
              Text(
                '${money(actual)} / ${money(ideal)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: over ? AppColors.rose : AppColors.inkSub,
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
              backgroundColor: AppColors.hair,
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
        groupHeader(label, trailing: total > 0 ? money(total) : null),
        if (items.isEmpty)
          cardGroup([
            _addTile(context, ref, cat, label),
          ])
        else
          cardGroup([
            for (var i = 0; i < items.length; i++) ...[
              _budgetRow(context, ref, items[i]),
              if (i != items.length - 1) rowDivider(),
            ],
            rowDivider(),
            _addTile(context, ref, cat, label),
          ]),
      ],
    );
  }

  Widget _budgetRow(BuildContext context, WidgetRef ref, Item item) {
    return DeletableRow(
      item: item,
      child: Material(
        color: AppColors.card,
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
                          fontSize: 15, fontWeight: FontWeight.w600)),
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
      color: AppColors.card,
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
