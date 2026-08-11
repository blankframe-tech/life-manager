import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/item.dart';

/// Section-brand accent colours — same hex in light and dark (checked for
/// 4.5:1 contrast against both surface tones).
class AppColors {
  static const indigo = Color(0xFF5B5BD6); // budget / brand
  static const teal = Color(0xFF14B8A6); // credit / they owe me
  static const rose = Color(0xFFF43F5E); // debt / i owe / destructive
  static const orange = Color(0xFFF97316); // tasks
  static const violet = Color(0xFF8B5CF6); // buy
  static const pink = Color(0xFFEC4899); // dreams
  static const green = Color(0xFF22C55E); // done / synced / online
}

/// Theme-aware surface/text tokens (light vs dark). Access via
/// `context.colors` — never reference these hex values directly in widgets.
class AppSurface extends ThemeExtension<AppSurface> {
  const AppSurface({
    required this.bg,
    required this.card,
    required this.ink,
    required this.inkSub,
    required this.hair,
  });

  final Color bg;
  final Color card;
  final Color ink;
  final Color inkSub;
  final Color hair;

  static const light = AppSurface(
    bg: Color(0xFFF2F2F7),
    card: Colors.white,
    ink: Color(0xFF1C1C1E),
    inkSub: Color(0xFF8E8E93),
    hair: Color(0xFFE5E5EA),
  );

  static const dark = AppSurface(
    bg: Color(0xFF0F172A),
    card: Color(0xFF192134),
    ink: Color(0xFFF8FAFC),
    inkSub: Color(0xFF94A3B8),
    hair: Color(0x14FFFFFF),
  );

  @override
  AppSurface copyWith({
    Color? bg,
    Color? card,
    Color? ink,
    Color? inkSub,
    Color? hair,
  }) {
    return AppSurface(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      ink: ink ?? this.ink,
      inkSub: inkSub ?? this.inkSub,
      hair: hair ?? this.hair,
    );
  }

  @override
  AppSurface lerp(ThemeExtension<AppSurface>? other, double t) {
    if (other is! AppSurface) return this;
    return AppSurface(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSub: Color.lerp(inkSub, other.inkSub, t)!,
      hair: Color.lerp(hair, other.hair, t)!,
    );
  }
}

extension AppSurfaceX on BuildContext {
  AppSurface get colors => Theme.of(this).extension<AppSurface>()!;
}

/// Describes one bottom-nav destination (which is one [ItemKind]).
class Section {
  final String kind;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;

  /// Whether this kind gets its own bottom-nav tab. `false` for kinds that
  /// are only reachable through another tab (e.g. Buy, absorbed into
  /// Dreams) but still need a styling entry for [sectionFor].
  final bool visibleInNav;

  /// When a tab represents more than one [ItemKind] (the merged Dreams tab
  /// covers both `buy` and `dream`), the FAB offers a choice between these
  /// instead of adding [kind] directly. Null/single-entry means "just add
  /// [kind]".
  final List<String>? addableKinds;

  const Section(this.kind, this.label, this.icon, this.activeIcon, this.color,
      {this.visibleInNav = true, this.addableKinds});
}

const kSections = <Section>[
  Section(ItemKind.budget, 'Budget', CupertinoIcons.chart_pie,
      CupertinoIcons.chart_pie_fill, AppColors.indigo),
  Section(ItemKind.deal, 'Dealings', CupertinoIcons.arrow_right_arrow_left,
      CupertinoIcons.arrow_right_arrow_left, AppColors.teal),
  Section(ItemKind.task, 'Tasks', CupertinoIcons.check_mark_circled,
      CupertinoIcons.check_mark_circled_solid, AppColors.orange),
  Section(ItemKind.buy, 'Buy', CupertinoIcons.bag, CupertinoIcons.bag_fill,
      AppColors.violet,
      visibleInNav: false),
  Section(ItemKind.dream, 'Dreams', CupertinoIcons.sparkles,
      CupertinoIcons.sparkles, AppColors.pink,
      addableKinds: [ItemKind.buy, ItemKind.dream]),
];

/// The tabs actually shown in the bottom nav, in display order.
final kNavSections = kSections.where((s) => s.visibleInNav).toList();

Section sectionFor(String kind) =>
    kSections.firstWhere((s) => s.kind == kind, orElse: () => kSections.first);

/// App-wide Material theme, tuned to feel native on iOS. Pass [Brightness.dark]
/// for the dark variant — both share the same shape, only tokens differ.
ThemeData buildTheme({Brightness brightness = Brightness.light}) {
  final surface = brightness == Brightness.dark ? AppSurface.dark : AppSurface.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorSchemeSeed: AppColors.indigo,
    scaffoldBackgroundColor: surface.bg,
    fontFamily: '.SF Pro Text',
    extensions: [surface],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: surface.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: surface.ink,
      titleTextStyle: TextStyle(
        color: surface.ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Rounded-rect "card group" decoration used throughout the lists.
BoxDecoration cardDecoration(BuildContext context) => BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
