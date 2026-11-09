import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/item_editor.dart';
import '../../widgets/module_nav.dart';
import '../category/category_module.dart';
import '../category/category_screen.dart';
import '../module.dart';

/// Tasks: a [CategoryModule] with due dates, plus an "Upcoming Tasks" card on
/// Home.
class TasksModule extends CategoryModule {
  const TasksModule()
    : super(
        id: 'tasks',
        kind: ItemKind.task,
        title: 'Tasks',
        singular: 'Task',
        icon: CupertinoIcons.checkmark_square,
        accent: Accents.lavender,
        dueDate: true,
        sections: const [
          ListSection('time', 'Time-sensitive', icon: CupertinoIcons.clock),
          ListSection(
            'admin',
            'Admin & tech chores',
            icon: CupertinoIcons.gear_alt,
          ),
          ListSection(
            'declutter',
            'Declutter, repairs & giving back',
            icon: CupertinoIcons.wrench,
          ),
        ],
        tagline: 'Plan. Prioritize. Get things done.',
        description:
            'Break down your day, set priorities, and stay focused on what matters.',
        features: const [
          IntroFeature(
            CupertinoIcons.slider_horizontal_3,
            'Smart groups',
            'Time-sensitive first, chores after.',
          ),
          IntroFeature(
            CupertinoIcons.calendar,
            'Due dates',
            'Never lose track of a deadline.',
          ),
          IntroFeature(
            CupertinoIcons.chart_bar_alt_fill,
            'Progress tracking',
            'See how many are left in each group.',
          ),
          IntroFeature(
            CupertinoIcons.eye_slash,
            'Focus mode',
            'Hide completed tasks with one switch.',
          ),
        ],
        emptyTitle: 'Nothing on your plate',
        emptySubtitle: 'Enjoy the calm — or add the next thing to get done.',
      );

  @override
  Widget? buildHomeCard(BuildContext context) => _UpcomingTasksCard(this);
}

class _UpcomingTasksCard extends ConsumerWidget {
  const _UpcomingTasksCard(this.module);
  final TasksModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(itemsProvider(module.kind)).valueOrNull ?? const [];
    final open = all.where((i) => !i.done).toList()
      ..sort((a, b) {
        final ad = a.dueDate, bd = b.dueDate;
        if (ad == null && bd == null) return a.sortOrder.compareTo(b.sortOrder);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    final shown = open.take(3).toList();
    final sections = {for (final s in module.sections) s.id: s};
    return SectionCard(
      title: 'Upcoming Tasks',
      onViewAll: () => openModule(context, ref, module),
      childPadding: const EdgeInsets.only(bottom: 6),
      child: shown.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
              child: Row(
                children: [
                  IconTile(
                    icon: CupertinoIcons.sun_max,
                    accent: Accents.butter,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'All clear. Enjoy the calm.',
                      style: context.text.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => showItemEditor(context, ref, module.kind),
                    child: const Text('Add'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  CategoryItemRow(
                    module: module,
                    item: shown[i],
                    section: sections[shown[i].section],
                  ),
                  if (i != shown.length - 1) rowDivider(context),
                ],
              ],
            ),
    );
  }
}
