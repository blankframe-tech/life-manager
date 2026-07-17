import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/item_editor.dart';
import 'budget_screen.dart';
import 'checklist_screen.dart';
import 'dealings_screen.dart';
import 'dreams_screen.dart';

/// The app shell: a bottom tab bar over the five sections. Screens stay mounted
/// (IndexedStack) so switching tabs never resets scroll or in-progress input.
class RootScaffold extends ConsumerStatefulWidget {
  const RootScaffold({super.key});

  @override
  ConsumerState<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends ConsumerState<RootScaffold> {
  int _index = 0;

  static const _screens = [
    BudgetScreen(),
    DealingsScreen(),
    ChecklistScreen(
      kind: ItemKind.task,
      groups: [
        (section: 'time', label: 'Time-sensitive'),
        (section: 'admin', label: 'Admin & tech chores'),
        (section: 'declutter', label: 'Declutter, repairs & giving back'),
      ],
      emptyIcon: CupertinoIcons.check_mark_circled,
      emptyTitle: 'No tasks',
      emptySubtitle: 'Add something you need to get done.',
    ),
    ChecklistScreen(
      kind: ItemKind.buy,
      groups: [
        (section: 'p0', label: 'Priority 0 · must asap'),
        (section: 'wishlist', label: 'Wishlist'),
      ],
      emptyIcon: CupertinoIcons.bag,
      emptyTitle: 'Nothing to buy',
      emptySubtitle: 'Add things you plan to purchase.',
    ),
    DreamsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final section = kSections[_index];
    final online = ref.watch(syncOnlineProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(section.label),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              online ? CupertinoIcons.cloud : CupertinoIcons.cloud_bolt,
              size: 20,
              color: online ? AppColors.green : AppColors.inkSub,
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showItemEditor(context, ref, section.kind),
        backgroundColor: section.color,
        elevation: 2,
        child: const Icon(CupertinoIcons.add, color: Colors.white),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: section.color.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final s in kSections)
              NavigationDestination(
                icon: Icon(s.icon),
                selectedIcon: Icon(s.activeIcon, color: s.color),
                label: s.label,
              ),
          ],
        ),
      ),
    );
  }
}
