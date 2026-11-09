import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../canvas/canvas_shell.dart';
import '../providers/providers.dart';
import '../widgets/app_nav_bar.dart';
import '../widgets/module_nav.dart';
import 'home_screen.dart';
import 'more_screen.dart';

/// The app shell. With a morphed canvas, the canvas; otherwise Home, the
/// configured nav modules, and More. Tabs stay mounted (IndexedStack) so
/// switching never resets scroll or input.
class RootScaffold extends ConsumerWidget {
  const RootScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(canvasProvider.select((s) => s.active))) {
      return const CanvasShell();
    }
    final nav = ref.watch(appConfigProvider).navModules;
    final ids = ['home', for (final m in nav) m.id, 'more'];
    final index = ids
        .indexOf(ref.watch(currentTabProvider))
        .clamp(0, ids.length - 1);
    return Scaffold(
      body: tabStack(index, [
        const HomeScreen(),
        for (final m in nav) ModulePage(key: ValueKey(m.id), module: m),
        const MoreScreen(),
      ]),
      bottomNavigationBar: AppNavBar(
        selectedIndex: index,
        onSelected: (i) {
          if (i > 0 && i <= nav.length) {
            ref.read(lastModuleProvider.notifier).state = nav[i - 1].id;
          }
          ref.read(currentTabProvider.notifier).state = ids[i];
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(CupertinoIcons.house),
            selectedIcon: Icon(CupertinoIcons.house_fill),
            label: 'Home',
          ),
          for (final m in nav)
            NavigationDestination(icon: Icon(m.icon), label: m.title),
          const NavigationDestination(
            icon: Icon(CupertinoIcons.ellipsis),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
