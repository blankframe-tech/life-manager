import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../../widgets/item_editor.dart';
import '../module.dart';
import 'category_module.dart';

/// The list screen for any [CategoryModule]: one card per section, done items
/// sinking to the bottom, a hide-completed switch, swipe to delete.
class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.module});

  final CategoryModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = module.kind;
    final async = ref.watch(itemsProvider(kind));
    final query = ref.watch(searchQueryProvider(kind));
    final hideDone = ref.watch(hideDoneProvider(kind));
    return async.when(
      loading: instantLoading,
      error: (e, _) =>
          errorState(context, () => ref.invalidate(itemsProvider(kind))),
      data: (all) {
        final searched = filterBySearch(all, query);
        if (searched.isEmpty) {
          return query.trim().isNotEmpty
              ? emptyState(
                  module.icon,
                  'No matches',
                  'Nothing here matches "${query.trim()}".',
                  accent: module.accent,
                )
              : emptyState(
                  module.icon,
                  module.emptyTitle ?? 'A fresh start',
                  module.emptySubtitle ??
                      'Add your first ${module.singular.toLowerCase()} — small steps count.',
                  onAction: () => showItemEditor(context, ref, kind),
                  actionLabel: 'Add ${module.singular.toLowerCase()}',
                  accent: module.accent,
                );
        }
        final items = hideDone
            ? searched.where((i) => !i.done).toList()
            : searched;
        final doneCount = searched.where((i) => i.done).length;
        final known = module.sections.map((s) => s.id).toSet();
        final rest = items
            .where((i) => !known.contains(i.section ?? ''))
            .toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            if (doneCount > 0) _hideDoneToggle(context, ref, doneCount),
            for (final s in module.sections)
              ..._group(
                context,
                ref,
                s.label,
                s,
                items.where((i) => i.section == s.id).toList(),
              ),
            ..._group(
              context,
              ref,
              module.sections.isEmpty ? module.title : 'Other',
              null,
              rest,
            ),
          ],
        );
      },
    );
  }

  Widget _hideDoneToggle(BuildContext context, WidgetRef ref, int doneCount) {
    final kind = module.kind;
    final hideDone = ref.watch(hideDoneProvider(kind));
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 12, 0),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Text(
                '$doneCount completed · Hide completed',
                style: context.text.bodySmall,
              ),
            ),
            Switch.adaptive(
              value: hideDone,
              onChanged: (v) =>
                  ref.read(hideDoneProvider(kind).notifier).state = v,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _group(
    BuildContext context,
    WidgetRef ref,
    String label,
    ListSection? section,
    List<Item> items,
  ) {
    if (items.isEmpty) return [];
    items.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1; // done sink to bottom
      return a.sortOrder.compareTo(b.sortOrder);
    });
    final remaining = items.where((i) => !i.done).length;
    return [
      groupHeader(context, label, trailing: '$remaining left'),
      cardGroup(context, [
        for (var i = 0; i < items.length; i++) ...[
          CategoryItemRow(module: module, item: items[i], section: section),
          if (i != items.length - 1) rowDivider(context),
        ],
      ]),
    ];
  }
}

final _due = DateFormat('EEE, d MMM');

/// "Today", "Tomorrow", or "Thu, 20 Aug".
String dueLabel(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  if (days == -1) return 'Yesterday';
  return _due.format(d);
}

/// One row: section icon tile, title + detail, amount, check circle.
class CategoryItemRow extends ConsumerWidget {
  const CategoryItemRow({
    super.key,
    required this.module,
    required this.item,
    this.section,
  });

  final CategoryModule module;
  final Item item;
  final ListSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final due = item.dueDate;
    final overdue =
        due != null &&
        !item.done &&
        due.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    final detail = [
      if (due != null) dueLabel(due),
      if (item.note.isNotEmpty) item.note,
    ].join(' · ');
    return DeletableRow(
      item: item,
      semanticLabel: [
        item.title,
        if (item.amount != null) money(item.amount),
        if (due != null) 'due ${dueLabel(due)}',
        if (overdue) 'overdue',
        if (item.done) 'done',
      ].join(', '),
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: () =>
              showItemEditor(context, ref, module.kind, existing: item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                IconTile(
                  icon: section?.icon ?? module.icon,
                  accent: module.accent,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  // The row's composed label already says all of this.
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: context.text.titleSmall!.copyWith(
                            fontWeight: FontWeight.w500,
                            color: item.done ? c.inkSub : c.ink,
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            detail,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall!.copyWith(
                              color: overdue ? c.negative : c.inkSub,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (item.amount != null) ...[
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Text(
                      money(item.amount),
                      style: context.text.titleSmall!.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
                CheckCircle(
                  done: item.done,
                  label: item.done
                      ? 'Mark ${item.title} as not done'
                      : 'Mark ${item.title} as done',
                  onChanged: (v) {
                    item.done = v;
                    ref.read(syncServiceProvider).save(item);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
