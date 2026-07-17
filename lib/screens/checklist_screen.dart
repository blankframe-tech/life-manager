import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';

/// A group definition: a `section` value and the header it renders under.
typedef ChecklistGroup = ({String section, String label});

/// Generic checked-list screen used by Tasks and Buy. Renders each group as a
/// card, with completed items sinking to the bottom and shown struck-through.
class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({
    super.key,
    required this.kind,
    required this.groups,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final String kind;
  final List<ChecklistGroup> groups;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(kind));
    return async.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) {
          return emptyState(emptyIcon, emptyTitle, emptySubtitle);
        }
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            for (final g in groups)
              ..._groupBlock(context, ref, g, _forGroup(items, g.section)),
            ..._ungrouped(context, ref, items),
          ],
        );
      },
    );
  }

  List<Item> _forGroup(List<Item> items, String section) {
    final list = items.where((i) => (i.section ?? '') == section).toList();
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1; // done sink to bottom
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return list;
  }

  List<Widget> _ungrouped(BuildContext context, WidgetRef ref, List<Item> items) {
    final known = groups.map((g) => g.section).toSet();
    final rest =
        items.where((i) => !known.contains(i.section ?? '')).toList();
    if (rest.isEmpty) return [];
    return _groupBlock(
        context, ref, (section: '', label: 'Other'), rest);
  }

  List<Widget> _groupBlock(BuildContext context, WidgetRef ref,
      ChecklistGroup g, List<Item> items) {
    if (items.isEmpty) return [];
    final remaining = items.where((i) => !i.done).length;
    return [
      groupHeader(g.label, trailing: '$remaining left'),
      cardGroup([
        for (var i = 0; i < items.length; i++) ...[
          _row(context, ref, items[i]),
          if (i != items.length - 1) rowDivider(),
        ],
      ]),
    ];
  }

  Widget _row(BuildContext context, WidgetRef ref, Item item) {
    final section = sectionFor(kind);
    return DeletableRow(
      item: item,
      child: Material(
        color: AppColors.card,
        child: InkWell(
          onTap: () => showItemEditor(context, ref, kind, existing: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    item.done = !item.done;
                    ref.read(syncServiceProvider).save(item);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12, top: 1),
                    child: Icon(
                      item.done
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.circle,
                      color: item.done ? section.color : AppColors.hair,
                      size: 24,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          color: item.done ? AppColors.inkSub : AppColors.ink,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(item.note,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.inkSub)),
                      ],
                      if (item.dueDate != null) ...[
                        const SizedBox(height: 6),
                        _dueBadge(item.dueDate!),
                      ],
                    ],
                  ),
                ),
                if (item.amount != null) ...[
                  const SizedBox(width: 10),
                  Text(money(item.amount),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dueBadge(DateTime due) {
    final now = DateTime.now();
    final soon = due.difference(now).inDays <= 3;
    final color = soon ? AppColors.rose : AppColors.inkSub;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.calendar, size: 12, color: color),
          const SizedBox(width: 4),
          Text(shortDate(due),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
