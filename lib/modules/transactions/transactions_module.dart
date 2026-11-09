import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../util/week.dart';
import '../../widgets/common.dart';
import '../../widgets/module_nav.dart';
import '../module.dart';
import 'transactions_screen.dart';
import 'txn_categories_screen.dart';

/// A log of money actually spent and earned, rolled up per week.
class TransactionsModule extends LifeModule {
  const TransactionsModule();

  @override
  String get id => 'transactions';
  @override
  String get title => 'Transactions';
  @override
  IconData get icon => CupertinoIcons.creditcard;
  @override
  ModuleAccent get accent => Accents.sky;

  @override
  List<ItemSpec> get items => const [
    ItemSpec(kind: ItemKind.txn, singular: 'Transaction', amount: true),
  ];

  @override
  ModuleIntro get intro => const ModuleIntro(
    tagline: 'Know where every taka goes.',
    description:
        'Log what you spend and earn in seconds, and see it add up week by week.',
    features: [
      IntroFeature(
        CupertinoIcons.tag,
        'Your categories',
        'Food, rent, transport — you decide.',
      ),
      IntroFeature(
        CupertinoIcons.calendar,
        'Weekly rollup',
        'In, out and left over, every week.',
      ),
      IntroFeature(
        CupertinoIcons.chart_bar_alt_fill,
        'Trends',
        'Eight weeks at a glance.',
      ),
      IntroFeature(
        CupertinoIcons.search,
        'Search',
        'Find any entry by name or category.',
      ),
    ],
  );

  @override
  Widget buildScreen(BuildContext context) => const TransactionsScreen();

  @override
  Widget? buildHomeCard(BuildContext context) => _WeekCard(this);

  @override
  Widget? buildSettings(BuildContext context) => Consumer(
    builder: (context, ref, _) => ListTile(
      leading: const Icon(CupertinoIcons.tag),
      title: const Text('Transaction categories'),
      subtitle: Text(
        '${ref.watch(txnCategoriesProvider).length} categories for the spend/earn log',
      ),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TxnCategoriesScreen())),
    ),
  );
}

class _WeekCard extends ConsumerWidget {
  const _WeekCard(this.module);
  final TransactionsModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(itemsProvider(ItemKind.txn)).valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    final start = startOfWeek(DateTime.now());
    final week = rollupByWeek(items).firstWhere(
      (w) => w.start == start,
      orElse: () => WeekRollup.empty(start),
    );
    final c = context.colors;
    return SectionCard(
      title: 'This Week',
      onViewAll: () => openModule(context, ref, module),
      child: Row(
        children: [
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Spent', style: context.text.bodySmall),
                  Text(
                    money(week.spent),
                    style: context.text.titleLarge!.copyWith(color: c.ink),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Earned', style: context.text.bodySmall),
                  Text(
                    money(week.earned),
                    style: context.text.titleLarge!.copyWith(color: c.positive),
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
