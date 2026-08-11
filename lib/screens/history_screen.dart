import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/history_event.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// A read-only log of every add / edit / complete / delete across all
/// screens — the answer to "what happened to my data over time?"
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity History')),
      body: async.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
          children: const [LoadingSkeleton()],
        ),
        error: (e, _) => errorState(context, () => ref.invalidate(historyProvider)),
        data: (events) {
          if (events.isEmpty) {
            return emptyState(
              CupertinoIcons.clock,
              'No activity yet',
              'Every add, edit, and delete will show up here.',
            );
          }
          final groups = _groupByDay(events);
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              for (final day in groups.keys) ...[
                groupHeader(context, day),
                cardGroup(context, [
                  for (var i = 0; i < groups[day]!.length; i++) ...[
                    _row(context, groups[day]![i]),
                    if (i != groups[day]!.length - 1) rowDivider(context),
                  ],
                ]),
              ],
            ],
          );
        },
      ),
    );
  }

  Map<String, List<HistoryEvent>> _groupByDay(List<HistoryEvent> events) {
    final groups = <String, List<HistoryEvent>>{};
    for (final e in events) {
      final label = _dayLabel(e.timestamp.toLocal());
      groups.putIfAbsent(label, () => []).add(e);
    }
    return groups;
  }

  String _dayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMMM yyyy').format(dt);
  }

  Widget _row(BuildContext context, HistoryEvent event) {
    final c = context.colors;
    final section = sectionFor(event.itemKind);
    return ListTile(
      leading: Icon(_icon(event.action), color: section.color),
      title: Text('${_verb(event.action)} "${event.title}"'),
      subtitle: Text(
          '${section.label} · ${DateFormat('h:mm a').format(event.timestamp.toLocal())}'),
      textColor: c.ink,
    );
  }

  String _verb(String action) {
    switch (action) {
      case HistoryAction.created:
        return 'Added';
      case HistoryAction.edited:
        return 'Edited';
      case HistoryAction.completed:
        return 'Completed';
      case HistoryAction.uncompleted:
        return 'Marked not done';
      case HistoryAction.deleted:
        return 'Deleted';
      default:
        return action;
    }
  }

  IconData _icon(String action) {
    switch (action) {
      case HistoryAction.created:
        return CupertinoIcons.add_circled;
      case HistoryAction.edited:
        return CupertinoIcons.pencil;
      case HistoryAction.completed:
        return CupertinoIcons.check_mark_circled_solid;
      case HistoryAction.uncompleted:
        return CupertinoIcons.circle;
      case HistoryAction.deleted:
        return CupertinoIcons.trash;
      default:
        return CupertinoIcons.circle;
    }
  }
}
