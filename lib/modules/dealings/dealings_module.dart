import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/module_nav.dart';
import '../module.dart';
import 'dealings_screen.dart';

/// Dena Paona — who owes whom.
class DealingsModule extends LifeModule {
  const DealingsModule();

  @override
  String get id => 'dealings';
  @override
  String get title => 'Dealings';
  @override
  IconData get icon => CupertinoIcons.arrow_right_arrow_left_circle;
  @override
  ModuleAccent get accent => Accents.sage;

  @override
  List<ItemSpec> get items => const [
    ItemSpec(kind: ItemKind.deal, singular: 'Dealing', amount: true),
  ];

  @override
  ModuleIntro get intro => const ModuleIntro(
    tagline: 'Dena Paona, sorted.',
    description:
        'Keep a calm, honest ledger of money you owe and money owed to you.',
    features: [
      IntroFeature(
        CupertinoIcons.arrow_up_circle,
        'Owed to me',
        'Never forget who borrowed what.',
      ),
      IntroFeature(
        CupertinoIcons.arrow_down_circle,
        'I owe',
        'Pay people back on time.',
      ),
      IntroFeature(
        CupertinoIcons.chart_bar_alt_fill,
        'Net position',
        'One number, with a breakdown chart.',
      ),
      IntroFeature(
        CupertinoIcons.doc_text,
        'Notes & assets',
        'Keep the details next to the amount.',
      ),
    ],
  );

  @override
  Widget buildScreen(BuildContext context) => const DealingsScreen();

  @override
  Widget? buildHomeCard(BuildContext context) => _NetCard(this);
}

class _NetCard extends ConsumerWidget {
  const _NetCard(this.module);
  final DealingsModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(itemsProvider(ItemKind.deal)).valueOrNull ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    double sum(String dir) => items
        .where((i) => i.direction == dir)
        .fold(0.0, (s, i) => s + (i.amount ?? 0));
    final owed = sum(DealDirection.theyOweMe);
    final owe = sum(DealDirection.iOweThem);
    final net = owed - owe;
    final c = context.colors;
    return SectionCard(
      title: 'Dealings',
      onViewAll: () => openModule(context, ref, module),
      child: Row(
        children: [
          _figure(context, 'Owed to me', money(owed), c.positive),
          _figure(context, 'I owe', money(owe), c.negative),
          _figure(
            context,
            'Net',
            '${net >= 0 ? '+' : '−'}${money(net.abs())}',
            c.ink,
          ),
        ],
      ),
    );
  }

  Widget _figure(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) => Expanded(
    child: MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.bodySmall),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: context.text.titleMedium!.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
