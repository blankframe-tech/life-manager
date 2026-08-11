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
import 'settings_screen.dart';

/// The app shell: a bottom tab bar over the five sections. Screens stay mounted
/// (IndexedStack) so switching tabs never resets scroll or in-progress input.
class RootScaffold extends ConsumerStatefulWidget {
  const RootScaffold({super.key});

  @override
  ConsumerState<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends ConsumerState<RootScaffold> {
  int _index = 0;
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _closeSearch(String kind) {
    _searchCtrl.clear();
    ref.read(searchQueryProvider(kind).notifier).state = '';
    setState(() => _searchOpen = false);
  }

  static const _addLabels = {
    ItemKind.buy: 'Add to shopping',
    ItemKind.dream: 'Add a dream',
  };

  void _handleAdd(BuildContext context, Section section) {
    final kinds = section.addableKinds;
    if (kinds == null || kinds.length <= 1) {
      showItemEditor(context, ref, section.kind);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in kinds)
              ListTile(
                leading:
                    Icon(sectionFor(kind).icon, color: sectionFor(kind).color),
                title: Text(_addLabels[kind] ?? 'Add'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showItemEditor(context, ref, kind);
                },
              ),
          ],
        ),
      ),
    );
  }

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
    DreamsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final section = kNavSections[_index];
    final online = ref.watch(syncOnlineProvider);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration.collapsed(hintText: 'Search'),
                onChanged: (v) =>
                    ref.read(searchQueryProvider(section.kind).notifier).state = v,
              )
            : Text(section.label),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close search' : 'Search',
            icon: Icon(_searchOpen ? CupertinoIcons.xmark : CupertinoIcons.search,
                size: 20),
            onPressed: () => _searchOpen
                ? _closeSearch(section.kind)
                : setState(() => _searchOpen = true),
          ),
          Semantics(
            label: online ? 'Sync online' : 'Sync offline',
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                online ? CupertinoIcons.cloud : CupertinoIcons.cloud_bolt,
                size: 20,
                color: online ? AppColors.green : c.inkSub,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(CupertinoIcons.gear, size: 22),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _handleAdd(context, section),
        backgroundColor: section.color,
        elevation: 2,
        child: const Icon(CupertinoIcons.add, color: Colors.white),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: c.card,
          indicatorColor: section.color.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (_searchOpen) _closeSearch(section.kind);
            setState(() => _index = i);
          },
          destinations: [
            for (final s in kNavSections)
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
