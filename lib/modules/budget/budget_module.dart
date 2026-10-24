import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../services/settings_service.dart' show BudgetSplit;
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/module_nav.dart';
import '../module.dart';
import 'budget_screen.dart';

/// A monthly Needs / Savings / Wants plan against your income.
class BudgetModule extends LifeModule {
  const BudgetModule();

  @override
  String get id => 'budget';
  @override
  String get title => 'Budget';
  @override
  IconData get icon => CupertinoIcons.chart_pie;
  @override
  ModuleAccent get accent => Accents.butter;

  @override
  List<ItemSpec> get items => const [
    ItemSpec(kind: ItemKind.budget, singular: 'Budget line', amount: true),
  ];

  @override
  ModuleIntro get intro => const ModuleIntro(
    tagline: 'Give every taka a job.',
    description:
        'Split your income into Needs, Savings and Wants, and see at a glance whether the plan fits.',
    features: [
      IntroFeature(
        CupertinoIcons.chart_pie,
        'Simple split',
        '65 / 20 / 15 by default — make it yours.',
      ),
      IntroFeature(
        CupertinoIcons.checkmark_circle,
        'Bills checklist',
        'Tick off Needs as you pay them; resets monthly.',
      ),
      IntroFeature(
        CupertinoIcons.arrow_up_right,
        'Over-budget alerts',
        'Know the moment a bucket overflows.',
      ),
      IntroFeature(
        CupertinoIcons.creditcard,
        'Recent spending',
        'This month’s transactions, right below.',
      ),
    ],
  );

  @override
  Widget buildScreen(BuildContext context) => const BudgetScreen();

  @override
  Widget? buildHomeCard(BuildContext context) => _DonutCard(this);

  @override
  Widget? buildSettings(BuildContext context) => const _BudgetSettings();
}

/// Home's "Monthly Budget" donut: the target split, with planned vs target
/// per bucket in the legend.
class _DonutCard extends ConsumerWidget {
  const _DonutCard(this.module);
  final BudgetModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(itemsProvider(ItemKind.budget)).valueOrNull ?? const [];
    final salary = ref.watch(monthlySalaryProvider);
    final split = ref.watch(budgetSplitProvider).byCategory;
    final planned = items.fold(0.0, (s, i) => s + (i.amount ?? 0));
    final share = salary == 0 ? 0 : (planned / salary * 100).round();
    final c = context.colors;
    final animate = !MediaQuery.of(context).disableAnimations;
    return SectionCard(
      title: 'Monthly Budget',
      trailing: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ActionChip(
          avatar: const Icon(CupertinoIcons.calendar, size: 15),
          label: Text(DateFormat('MMMM').format(DateTime.now())),
          tooltip: 'Open budget',
          onPressed: () => openModule(context, ref, module),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openModule(context, ref, module),
        child: Row(
          children: [
            Semantics(
              label: '$share percent of income planned',
              excludeSemantics: true,
              child: SizedBox(
                width: 136,
                height: 136,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        startDegreeOffset: -90,
                        sectionsSpace: 2,
                        centerSpaceRadius: 44,
                        sections: [
                          for (final b in kBuckets)
                            PieChartSectionData(
                              value: ((split[b.cat] ?? 0) * 100)
                                  .clamp(0.01, 100)
                                  .toDouble(),
                              color: b.accent.chart,
                              radius: 20,
                              showTitle: false,
                            ),
                        ],
                      ),
                      duration: animate
                          ? const Duration(milliseconds: 500)
                          : Duration.zero,
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$share%', style: context.text.headlineSmall),
                        Text('of income', style: context.text.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  for (final b in kBuckets)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: MergeSemantics(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: b.accent.chart,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          b.label,
                                          style: context.text.bodyMedium,
                                        ),
                                      ),
                                      Text(
                                        '${((split[b.cat] ?? 0) * 100).round()}%',
                                        style: context.text.bodyMedium,
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${money(plannedFor(items, b.cat))} / ${money(salary * (split[b.cat] ?? 0))}',
                                    style: context.text.bodySmall!.copyWith(
                                      color: c.inkSub,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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

/// Settings → Budget: monthly income and the target split.
class _BudgetSettings extends ConsumerStatefulWidget {
  const _BudgetSettings();

  @override
  ConsumerState<_BudgetSettings> createState() => _BudgetSettingsState();
}

class _BudgetSettingsState extends ConsumerState<_BudgetSettings> {
  late final _salary = TextEditingController(
    text: ref.read(monthlySalaryProvider).toStringAsFixed(0),
  );
  late final _split = ref.read(budgetSplitProvider);
  late final _needs = TextEditingController(text: _pct(_split.needs));
  late final _wants = TextEditingController(text: _pct(_split.wants));
  late final _savings = TextEditingController(text: _pct(_split.savings));

  static String _pct(double frac) => (frac * 100).round().toString();

  @override
  void dispose() {
    _salary.dispose();
    _needs.dispose();
    _wants.dispose();
    _savings.dispose();
    super.dispose();
  }

  void _saveSalary() {
    final v = double.tryParse(_salary.text.trim());
    if (v != null && v > 0) ref.read(monthlySalaryProvider.notifier).set(v);
  }

  int _sum() {
    int p(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    return p(_needs) + p(_wants) + p(_savings);
  }

  void _saveSplit() {
    final n = int.tryParse(_needs.text.trim());
    final w = int.tryParse(_wants.text.trim());
    final s = int.tryParse(_savings.text.trim());
    if (n == null || w == null || s == null || n < 0 || w < 0 || s < 0) return;
    ref
        .read(budgetSplitProvider.notifier)
        .set(BudgetSplit(needs: n / 100, wants: w / 100, savings: s / 100));
    setState(() {});
  }

  Widget _splitField(String label, TextEditingController ctrl) => Expanded(
    child: TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _saveSplit(),
      onEditingComplete: _saveSplit,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sum = _sum();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _salary,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Monthly income (৳)',
              helperText: 'Used for the budget split below',
            ),
            onSubmitted: (_) => _saveSalary(),
            onEditingComplete: _saveSalary,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _splitField('Needs %', _needs),
              const SizedBox(width: 10),
              _splitField('Wants %', _wants),
              const SizedBox(width: 10),
              _splitField('Savings %', _savings),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            sum == 100
                ? 'Splits add up to 100%'
                : 'Splits add up to $sum% — should be 100%',
            style: context.text.bodySmall!.copyWith(
              color: sum == 100 ? null : context.colors.negative,
            ),
          ),
        ],
      ),
    );
  }
}
