import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/module_nav.dart';
import 'home_screen.dart';
import 'more_screen.dart';

/// The app shell: Home, the configured nav modules, and More. Tabs stay
/// mounted (IndexedStack) so switching never resets scroll or input.
class RootScaffold extends ConsumerWidget {
  const RootScaffold({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(appConfigProvider).navModules;
    final ids = ['home', for (final m in nav) m.id, 'more'];
    final index = ids
        .indexOf(ref.watch(currentTabProvider))
        .clamp(0, ids.length - 1);
    final pages = <Widget>[
      const HomeScreen(),
      for (final m in nav) ModulePage(key: ValueKey(m.id), module: m),
      const MoreScreen(),
    ];
    final c = context.colors;
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < pages.length; i++)
            // Only the visible tab takes part in hero flights / tickers, so a
            // hidden tab can't collide with the visible one's hero tags.
            HeroMode(
              enabled: i == index,
              child: TickerMode(enabled: i == index, child: pages[i]),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: c.card,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Accents.forest.softOf(context),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              size: 24,
              color: s.contains(WidgetState.selected) ? c.primary : c.inkSub,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => context.text.labelSmall!.copyWith(
              color: s.contains(WidgetState.selected) ? c.primary : c.inkSub,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
            ),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.hair)),
          ),
          child: NavigationBar(
            height: 68,
            selectedIndex: index,
            onDestinationSelected: (i) {
              HapticFeedback.selectionClick();
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
        ),
      ),
    );
  }
}
