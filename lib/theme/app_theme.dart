import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/item.dart';

/// Central palette + per-section metadata. iOS-first look: soft grouped
/// background, white cards, rounded corners, restrained accent colours.
class AppColors {
  static const bg = Color(0xFFF2F2F7); // iOS system grouped background
  static const card = Colors.white;
  static const ink = Color(0xFF1C1C1E); // primary label
  static const inkSub = Color(0xFF8E8E93); // secondary label
  static const hair = Color(0xFFE5E5EA); // separator

  static const indigo = Color(0xFF5B5BD6); // budget / brand
  static const teal = Color(0xFF14B8A6); // credit / they owe me
  static const rose = Color(0xFFF43F5E); // debt / i owe
  static const orange = Color(0xFFF97316); // tasks
  static const violet = Color(0xFF8B5CF6); // buy
  static const pink = Color(0xFFEC4899); // dreams
  static const green = Color(0xFF22C55E); // done / synced
}

/// Describes one bottom-nav destination (which is one [ItemKind]).
class Section {
  final String kind;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color color;
  const Section(this.kind, this.label, this.icon, this.activeIcon, this.color);
}

const kSections = <Section>[
  Section(ItemKind.budget, 'Budget', CupertinoIcons.chart_pie,
      CupertinoIcons.chart_pie_fill, AppColors.indigo),
  Section(ItemKind.deal, 'Dealings', CupertinoIcons.arrow_right_arrow_left,
      CupertinoIcons.arrow_right_arrow_left, AppColors.teal),
  Section(ItemKind.task, 'Tasks', CupertinoIcons.check_mark_circled,
      CupertinoIcons.check_mark_circled_solid, AppColors.orange),
  Section(ItemKind.buy, 'Buy', CupertinoIcons.bag, CupertinoIcons.bag_fill,
      AppColors.violet),
  Section(ItemKind.dream, 'Dreams', CupertinoIcons.sparkles,
      CupertinoIcons.sparkles, AppColors.pink),
];

Section sectionFor(String kind) =>
    kSections.firstWhere((s) => s.kind == kind, orElse: () => kSections.first);

/// App-wide Material theme, tuned to feel native on iOS.
ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.indigo,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: '.SF Pro Text',
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: AppColors.ink,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
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
BoxDecoration cardDecoration() => BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );
