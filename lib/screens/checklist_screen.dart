import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.shrinkWrap = false,
    this.physics,
    this.searchKind,
  });

  final String kind;
  final List<ChecklistGroup> groups;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptySubtitle;

  /// Set when this screen is nested (non-scrolling) inside another list —
  /// e.g. the Shopping section embedded in the merged Dreams tab.
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  /// Provider key to read the search query from. Defaults to [kind]; the
  /// merged Dreams tab overrides this so one search box filters both its
  /// Shopping section and its Dreams cards.
  final String? searchKind;

  /// Bounds a [Center]-based state (empty/error) so it doesn't throw when
  /// nested inside an outer unbounded list ([shrinkWrap]).
  Widget _bounded(Widget child) =>
      shrinkWrap ? SizedBox(height: 200, child: child) : child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(kind));
    final query = ref.watch(searchQueryProvider(searchKind ?? kind));
    final hideDone = ref.watch(hideDoneProvider(kind));
    return async.when(
      loading: () => shrinkWrap
          ? const Padding(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 16),
              child: LoadingSkeleton(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
              children: const [LoadingSkeleton()],
            ),
      error: (e, _) => _bounded(
          errorState(context, () => ref.invalidate(itemsProvider(kind)))),
      data: (all) {
        final searched = filterBySearch(all, query);
        if (searched.isEmpty) {
          return _bounded(emptyState(
            emptyIcon,
            emptyTitle,
            emptySubtitle,
            onAction: () => showItemEditor(context, ref, kind),
            actionLabel: 'Add',
          ));
        }
        final items =
            hideDone ? searched.where((i) => !i.done).toList() : searched;
        final doneCount = searched.where((i) => i.done).length;
        return ListView(
          shrinkWrap: shrinkWrap,
          physics: physics ?? const BouncingScrollPhysics(),
          padding: shrinkWrap ? EdgeInsets.zero : const EdgeInsets.only(bottom: 96),
          children: [
            if (doneCount > 0) _hideDoneToggle(context, ref, doneCount),
            for (final g in groups)
              ..._groupBlock(context, ref, g, _forGroup(items, g.section)),
            ..._ungrouped(context, ref, items),
          ],
        );
      },
    );
  }

  Widget _hideDoneToggle(BuildContext context, WidgetRef ref, int doneCount) {
    final hideDone = ref.watch(hideDoneProvider(kind));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text('$doneCount completed',
                style: TextStyle(fontSize: 13, color: context.colors.inkSub)),
          ),
          Text('Hide completed',
              style: TextStyle(fontSize: 13, color: context.colors.inkSub)),
          Switch(
            value: hideDone,
            onChanged: (v) => ref.read(hideDoneProvider(kind).notifier).state = v,
          ),
        ],
      ),
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
      groupHeader(context, g.label, trailing: '$remaining left'),
      cardGroup(context, [
        for (var i = 0; i < items.length; i++) ...[
          _row(context, ref, items[i]),
          if (i != items.length - 1) rowDivider(context),
        ],
      ]),
    ];
  }

  Widget _row(BuildContext context, WidgetRef ref, Item item) {
    final section = sectionFor(kind);
    final c = context.colors;
    return DeletableRow(
      item: item,
      semanticLabel:
          '${item.title}${item.done ? ', done' : ''}${item.dueDate != null ? ', due ${shortDate(item.dueDate!)}' : ''}',
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: () => showItemEditor(context, ref, kind, existing: item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: item.done ? 'Mark as not done' : 'Mark as done',
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      item.done = !item.done;
                      ref.read(syncServiceProvider).save(item);
                    },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            item.done
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.circle,
                            color: item.done ? section.color : c.hair,
                            size: 24,
                          ),
                        ),
                      ),
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
                          color: item.done ? c.inkSub : c.ink,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (item.note.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(item.note,
                            style: TextStyle(fontSize: 13, color: c.inkSub)),
                      ],
                      if (item.dueDate != null) ...[
                        const SizedBox(height: 6),
                        _dueBadge(context, item.dueDate!),
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

  Widget _dueBadge(BuildContext context, DateTime due) {
    final now = DateTime.now();
    final soon = due.difference(now).inDays <= 3;
    final color = soon ? AppColors.rose : context.colors.inkSub;
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
