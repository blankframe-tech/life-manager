import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/app_modules.dart';
import 'package:life_manager/modules/category/category_module.dart';
import 'package:life_manager/modules/module.dart';
import 'package:life_manager/screens/root_scaffold.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:life_manager/widgets/module_nav.dart';

import 'v2_helpers.dart';

/// The example from docs/MODULES.md — a new category is one config entry.
const books = CategoryModule(
  id: 'books',
  title: 'Reading',
  singular: 'Book',
  icon: CupertinoIcons.book,
  accent: Accents.sky,
  sections: [ListSection('now', 'Reading now'), ListSection('next', 'Up next')],
);

Finder navLabel(String text) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(text));

void main() {
  testWidgets('the default config puts Budget in the nav and on Home', (
    tester,
  ) async {
    await pumpV2(tester, const RootScaffold());

    expect(navLabel('Budget'), findsOneWidget);
    expect(navLabel('Tasks'), findsOneWidget);
    expect(find.text('Monthly Budget'), findsOneWidget);
  });

  testWidgets(
    'removing a module from the config removes it from nav and home',
    (tester) async {
      final config = AppConfig(
        modules: kAppConfig.modules.where((m) => m.id != 'budget').toList(),
        navIds: kAppConfig.navIds,
      );
      await pumpV2(tester, const RootScaffold(), config: config);

      expect(navLabel('Budget'), findsNothing);
      expect(find.text('Monthly Budget'), findsNothing);
      expect(find.text('Budget'), findsNothing);
      // Everything else still renders.
      expect(navLabel('Tasks'), findsOneWidget);
      expect(navLabel('Notes'), findsOneWidget);
      expect(find.text('Upcoming Tasks'), findsOneWidget);
    },
  );

  testWidgets('reordering the config reorders the home tiles', (tester) async {
    final config = AppConfig(
      modules: kAppConfig.modules.reversed.toList(),
      navIds: const ['dreams'],
    );
    await pumpV2(tester, const RootScaffold(), config: config);

    final dreams = tester.getTopLeft(find.text('Dreams').first);
    final buy = tester.getTopLeft(find.text('Buy').first);
    expect(dreams.dx, lessThan(buy.dx));
    expect(navLabel('Dreams'), findsOneWidget);
    expect(navLabel('Budget'), findsNothing);
  });

  testWidgets('a generic category config renders its sections and items', (
    tester,
  ) async {
    await pumpV2(
      tester,
      const ModulePage(module: books, pushed: true),
      config: const AppConfig(modules: [books]),
      items: [
        item('books', 'Dune', section: 'now'),
        item('books', 'Piranesi', section: 'next'),
      ],
    );

    expect(find.text('Reading'), findsOneWidget); // app bar
    expect(find.text('Reading now'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Piranesi'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Mark Dune as done'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a module shows its intro first, then its screen', (
    tester,
  ) async {
    await pumpV2(
      tester,
      const ModulePage(module: books, pushed: true),
      config: const AppConfig(modules: [books]),
      introsSeen: const [],
    );

    expect(find.text('Explore Reading'), findsOneWidget);
    await tester.tap(find.text('Explore Reading'));
    await tester.pumpAndSettle();
    expect(find.text('A fresh start'), findsOneWidget);
    expect(find.byTooltip('Add book'), findsOneWidget);
  });

  test('nav ids for removed modules are ignored, and nav caps at 3', () {
    final config = AppConfig(
      modules: kAppConfig.modules,
      navIds: const ['gone', 'notes', 'budget', 'tasks', 'buy'],
    );
    expect(config.navModules.map((m) => m.id), ['notes', 'budget', 'tasks']);
    expect(config.specFor('books'), isNull);
    expect(
      const AppConfig(modules: [books]).specFor('books')!.singular,
      'Book',
    );
  });
}
