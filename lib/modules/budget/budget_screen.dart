import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/item_editor.dart';
import '../../widgets/module_nav.dart';

/// One budget bucket's presentation. Order here is display order.
typedef Bucket = ({
  String cat,
  String label,
  IconData icon,
  ModuleAccent accent,
});

const kBuckets = <Bucket>[
  (
    cat: BudgetCategory.needs,
    label: 'Needs',
    icon: CupertinoIcons.house,
    accent: Accents.sage,
  ),
  (
    cat: BudgetCategory.savings,
    label: 'Savings',
    icon: CupertinoIcons.shield,
    accent: Accents.butter,
  ),
  (
    cat: BudgetCategory.wants,
    label: 'Wants',
    icon: CupertinoIcons.bag,
    accent: Accents.rose,
  ),
];

/// Month shown by the Budget screen's switcher (drives Recent Transactions).
final budgetMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

final _monthLabel = DateFormat('MMMM yyyy');
final _dayLabel = DateFormat('MMM d');

double plannedFor(List<Item> items, String cat) => items
    .where((i) => i.category == cat)
    .fold(0.0, (s, i) => s + (i.amount ?? 0));

/// The monthly plan: income, the three buckets, and this month's spending.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(ItemKind.budget));
    final query = ref.watch(searchQueryProvider(ItemKind.budget));
    return async.when(
      loading: instantLoading,
      error: (e, _) => errorState(
        context,
        () => ref.invalidate(itemsProvider(ItemKind.budget)),
      ),
      data: (items) {
        if (query.trim().isNotEmpty) {
          return _searchResults(context, filterBySearch(items, query));
        }
        final salary = ref.watch(monthlySalaryProvider);
        final split = ref.watch(budgetSplitProvider).byCategory;
        final planned = items.fold(0.0, (s, i) => s + (i.amount ?? 0));
        final showTxns =
            ref.watch(appConfigProvider).moduleForKind(ItemKind.txn) != null;
        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            if (showTxns) const _MonthSwitcher(),
            _IncomeCard(salary: salary, planned: planned),
            const SizedBox(height: 14),
            for (final b in kBuckets)
              _BucketCard(
                bucket: b,
                pct: split[b.cat] ?? 0,
                salary: salary,
                planned: plannedFor(items, b.cat),
                count: items.where((i) => i.category == b.cat).length,
              ),
            if (showTxns) ...[
              const SizedBox(height: 6),
              const _RecentTransactions(),
            ],
          ],
        );
      },
    );
  }

  Widget _searchResults(BuildContext context, List<Item> found) {
    if (found.isEmpty) {
      return emptyState(
        CupertinoIcons.search,
        'No matches',
        'No budget lines match your search.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 120),
      children: [
        cardGroup(context, [
          for (var i = 0; i < found.length; i++) ...[
            BudgetRow(item: found[i]),
            if (i != found.length - 1) rowDivider(context),
          ],
        ]),
      ],
    );
  }
}

class _MonthSwitcher extends ConsumerWidget {
  const _MonthSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    void shift(int by) {
      HapticFeedback.selectionClick();
      ref.read(budgetMonthProvider.notifier).state = DateTime(
        month.year,
        month.month + by,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => shift(-1),
            icon: const Icon(CupertinoIcons.chevron_left, size: 18),
          ),
          Expanded(
            child: Text(
              _monthLabel.format(month),
              textAlign: TextAlign.center,
              style: context.text.titleSmall,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: () => shift(1),
            icon: const Icon(CupertinoIcons.chevron_right, size: 18),
          ),
        ],
      ),
    );
  }
}

class _IncomeCard extends ConsumerWidget {
  const _IncomeCard({required this.salary, required this.planned});
  final double salary;
  final double planned;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final over = planned > salary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 16, 14, 18),
      decoration: cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Income', style: context.text.bodySmall),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(salary),
                          style: context.text.headlineMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ActionChip(
                label: const Text('Edit'),
                tooltip: 'Edit monthly income',
                onPressed: () => editSalary(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SoftBar(
            value: salary == 0 ? 0 : planned / salary,
            color: over ? c.negative : c.primary,
          ),
          const SizedBox(height: 8),
          Text(
            over
                ? '${money(planned)} planned · ${money(planned - salary)} over income'
                : '${money(planned)} planned · ${money(salary - planned)} unassigned',
            style: context.text.bodySmall!.copyWith(
              color: over ? c.negative : c.inkSub,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog to change the monthly income the split is computed from.
Future<void> editSalary(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController(
    text: ref.read(monthlySalaryProvider).toStringAsFixed(0),
  );
  final value = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Monthly income'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(prefixText: '৳ '),
        onSubmitted: (t) => Navigator.pop(ctx, double.tryParse(t.trim())),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, double.tryParse(ctrl.text.trim())),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  ctrl.dispose();
  if (value != null && value > 0) {
    HapticFeedback.lightImpact();
    ref.read(monthlySalaryProvider.notifier).set(value);
  }
}

class _BucketCard extends StatelessWidget {
  const _BucketCard({
    required this.bucket,
    required this.pct,
    required this.salary,
    required this.planned,
    required this.count,
  });

  final Bucket bucket;
  final double pct;
  final double salary;
  final double planned;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final target = salary * pct;
    final over = planned > target;
    final a = bucket.accent;
    final pctText = '${(pct * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Semantics(
        button: true,
        label:
            '${bucket.label}, target $pctText, ${money(target)}. '
            '${money(planned)} planned${over ? ', over target' : ''}. '
            '$count items.',
        excludeSemantics: true,
        child: Material(
          color: a.softOf(context),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BudgetBucketPage(bucket: bucket),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: c.card.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(bucket.icon, color: a.inkOf(context), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bucket.label, style: context.text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          '$pctText • ${money(target)}',
                          style: context.text.bodySmall!.copyWith(
                            color: c.ink.withValues(alpha: 0.75),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SoftBar(
                          value: target == 0 ? 0 : planned / target,
                          color: over ? c.negative : a.chart,
                          track: c.card.withValues(alpha: 0.8),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          over
                              ? '↑ ${money(planned)} planned — ${money(planned - target)} over'
                              : '${money(planned)} planned',
                          style: context.text.labelSmall!.copyWith(
                            color: over
                                ? c.negative
                                : c.ink.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 18, color: c.inkSub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentTransactions extends ConsumerWidget {
  const _RecentTransactions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(budgetMonthProvider);
    final all = ref.watch(itemsProvider(ItemKind.txn)).valueOrNull ?? const [];
    final inMonth =
        all
            .where(
              (i) =>
                  i.occurredAt.year == month.year &&
                  i.occurredAt.month == month.month,
            )
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final txnModule = ref.watch(appConfigProvider).moduleForKind(ItemKind.txn);
    final c = context.colors;
    return SectionCard(
      title: 'Recent Transactions',
      onViewAll: txnModule == null
          ? null
          : () => openModule(context, ref, txnModule),
      childPadding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: inMonth.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No transactions in ${_monthLabel.format(month)}.',
                style: context.text.bodySmall,
              ),
            )
          : Column(
              children: [
                for (final t in inMonth.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: MergeSemantics(
                      child: Row(
                        children: [
                          IconTile(
                            icon: t.isEarning
                                ? CupertinoIcons.arrow_down_left
                                : CupertinoIcons.cart,
                            accent: categoryAccent(t.category ?? ''),
                            size: 38,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.text.titleSmall!.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  t.category ?? 'Uncategorised',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${t.isEarning ? '+' : '−'}${money(t.amount)}',
                                style: context.text.titleSmall!.copyWith(
                                  color: t.isEarning ? c.positive : c.ink,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                _dayLabel.format(t.occurredAt),
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One bucket's lines (rent, groceries…), with paid-checkboxes for Needs.
class BudgetBucketPage extends ConsumerWidget {
  const BudgetBucketPage({super.key, required this.bucket});
  final Bucket bucket;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all =
        ref.watch(itemsProvider(ItemKind.budget)).valueOrNull ?? const [];
    final items = all.where((i) => i.category == bucket.cat).toList();
    final salary = ref.watch(monthlySalaryProvider);
    final pct = ref.watch(budgetSplitProvider).byCategory[bucket.cat] ?? 0;
    final planned = plannedFor(items, bucket.cat);
    final checkable = bucket.cat == BudgetCategory.needs;
    final paid = items.where((i) => i.done).length;
    void add() => showItemEditor(
      context,
      ref,
      ItemKind.budget,
      initialCategory: bucket.cat,
    );
    return Scaffold(
      appBar: AppBar(title: Text(bucket.label)),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: 'Add to ${bucket.label}',
        onPressed: () {
          HapticFeedback.lightImpact();
          add();
        },
        child: const Icon(CupertinoIcons.add),
      ),
      body: items.isEmpty
          ? emptyState(
              bucket.icon,
              'Nothing planned yet',
              'Add the ${bucket.label.toLowerCase()} you expect this month.',
              onAction: add,
              actionLabel: 'Add to ${bucket.label}',
              accent: bucket.accent,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                groupHeader(
                  context,
                  '${money(planned)} of ${money(salary * pct)} target',
                  trailing: checkable ? '$paid/${items.length} paid' : null,
                ),
                cardGroup(context, [
                  for (var i = 0; i < items.length; i++) ...[
                    BudgetRow(item: items[i]),
                    if (i != items.length - 1) rowDivider(context),
                  ],
                ]),
              ],
            ),
    );
  }
}

/// A budget line. Needs rows get a paid-checkbox (reset monthly).
class BudgetRow extends ConsumerWidget {
  const BudgetRow({super.key, required this.item});
  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final checkable = item.category == BudgetCategory.needs;
    final struck = checkable && item.done;
    return DeletableRow(
      item: item,
      semanticLabel:
          '${item.title}'
          '${item.amount != null ? ', ${money(item.amount)}' : ''}'
          '${checkable ? (item.done ? ', paid' : ', not paid') : ''}',
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: () =>
              showItemEditor(context, ref, ItemKind.budget, existing: item),
          child: Padding(
            padding: EdgeInsets.fromLTRB(checkable ? 4 : 16, 8, 16, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  if (checkable)
                    CheckCircle(
                      done: item.done,
                      label: item.done
                          ? 'Mark ${item.title} as not paid'
                          : 'Mark ${item.title} as paid',
                      onChanged: (v) {
                        item.done = v;
                        ref.read(syncServiceProvider).save(item);
                      },
                    ),
                  Expanded(
                    child: Text(
                      item.title,
                      style: context.text.bodyLarge!.copyWith(
                        color: struck ? c.inkSub : c.ink,
                        decoration: struck ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (item.amount != null) ...[
                    const SizedBox(width: 12),
                    Text(
                      money(item.amount),
                      style: context.text.titleSmall!.copyWith(
                        color: struck ? c.inkSub : c.ink,
                        decoration: struck ? TextDecoration.lineThrough : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
