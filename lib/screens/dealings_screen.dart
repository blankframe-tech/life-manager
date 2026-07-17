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
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) {
          return emptyState(CupertinoIcons.arrow_right_arrow_left,
              'No dealings', 'Track money you owe and money owed to you.');
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
            _balanceCard(oweTotal, owedTotal),
            if (iOwe.isNotEmpty) ...[
              groupHeader('I owe', trailing: money(oweTotal)),
              cardGroup(_rows(context, ref, iOwe)),
            ],
            if (theyOwe.isNotEmpty) ...[
              groupHeader('Owed to me', trailing: money(owedTotal)),
              cardGroup(_rows(context, ref, theyOwe)),
            ],
            if (other.isNotEmpty) ...[
              groupHeader('Notes & assets'),
              cardGroup(_rows(context, ref, other)),
            ],
          ],
        );
      },
    );
  }

  double _sum(List<Item> l) => l.fold(0.0, (s, i) => s + (i.amount ?? 0));

  Widget _balanceCard(double owe, double owed) {
    final net = owed - owe;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              _stat('I owe', owe, AppColors.rose),
              Container(width: 1, height: 40, color: AppColors.hair),
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
        ],
      ),
    );
  }

  Widget _stat(String label, double v, Color c) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.inkSub, fontSize: 13)),
          const SizedBox(height: 4),
          Text(money(v),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }

  List<Widget> _rows(BuildContext context, WidgetRef ref, List<Item> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(_row(context, ref, items[i]));
      if (i != items.length - 1) out.add(rowDivider());
    }
    return out;
  }

  Widget _row(BuildContext context, WidgetRef ref, Item item) {
    final owe = item.direction == DealDirection.iOweThem;
    final color = item.direction == null
        ? AppColors.inkSub
        : (owe ? AppColors.rose : AppColors.teal);
    return DeletableRow(
      item: item,
      child: Material(
        color: AppColors.card,
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
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.inkSub)),
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
                        color: color),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
