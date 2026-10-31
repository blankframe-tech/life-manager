import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The app's bottom navigation bar, shared by the module shell and the
/// canvas: card background, hairline top border, forest selection.
class AppNavBar extends StatelessWidget {
  const AppNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return NavigationBarTheme(
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
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            onSelected(i);
          },
          destinations: destinations,
        ),
      ),
    );
  }
}

/// The visible page of an [IndexedStack] of tabs. Only the visible tab takes
/// part in hero flights and tickers, so a hidden tab can't collide with it.
Widget tabStack(int index, List<Widget> pages) => IndexedStack(
  index: index,
  children: [
    for (var i = 0; i < pages.length; i++)
      HeroMode(
        enabled: i == index,
        child: TickerMode(enabled: i == index, child: pages[i]),
      ),
  ],
);
