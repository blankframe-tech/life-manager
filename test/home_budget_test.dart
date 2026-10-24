import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/modules/budget/budget_screen.dart';
import 'package:life_manager/screens/home_screen.dart';
import 'package:life_manager/theme/app_theme.dart';

import 'v2_helpers.dart';

void main() {
  group('greetingFor', () {
    test('follows the time of day', () {
      expect(greetingFor(DateTime(2026, 1, 1, 7)), 'Good morning');
      expect(greetingFor(DateTime(2026, 1, 1, 13)), 'Good afternoon');
      expect(greetingFor(DateTime(2026, 1, 1, 20)), 'Good evening');
      expect(greetingFor(DateTime(2026, 1, 1, 2)), 'Good evening');
    });
  });

  testWidgets('home greets by name and shows budget and task cards', (
    tester,
  ) async {
    await pumpV2(
      tester,
      const HomeScreen(),
      prefs: {'user_name': 'Nafiz', 'monthly_salary': 50000.0},
      items: [
        item(
          ItemKind.task,
          'Guitar practice',
          section: 'time',
          due: DateTime.now(),
        ),
        item(ItemKind.task, 'Old done thing', done: true),
        item(
          ItemKind.budget,
          'Rent',
          amount: 20000,
          category: BudgetCategory.needs,
        ),
      ],
    );

    expect(find.textContaining(', Nafiz'), findsOneWidget);
    expect(find.text("Here's your overview for today."), findsOneWidget);
    expect(find.text('Monthly Budget'), findsOneWidget);
    expect(find.text('৳20,000 / ৳32,500'), findsOneWidget); // needs
    expect(find.text('Upcoming Tasks'), findsOneWidget);
    expect(find.text('Guitar practice'), findsOneWidget);
    expect(find.text('Old done thing'), findsNothing);
    expect(find.byTooltip('Quick add'), findsOneWidget);
  });

  testWidgets('home shows an encouraging state when nothing is due', (
    tester,
  ) async {
    await pumpV2(tester, const HomeScreen());
    expect(find.text('All clear. Enjoy the calm.'), findsOneWidget);
  });

  testWidgets('budget shows income, three buckets and the month\'s spending', (
    tester,
  ) async {
    final now = DateTime.now();
    await pumpV2(
      tester,
      const Scaffold(body: BudgetScreen()),
      prefs: {'monthly_salary': 50000.0},
      items: [
        item(
          ItemKind.budget,
          'Rent',
          amount: 40000,
          category: BudgetCategory.needs,
        ),
        item(
          ItemKind.txn,
          'Super Shop',
          amount: 1250,
          category: 'Groceries',
          direction: TxnDirection.spend,
          due: now,
        ),
      ],
    );

    expect(find.text('Total Income'), findsOneWidget);
    expect(find.text('৳50,000'), findsOneWidget);
    expect(find.text('Needs'), findsOneWidget);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Wants'), findsOneWidget);
    expect(find.text('65% • ৳32,500'), findsOneWidget);
    // Over target is said in words, not colour alone.
    expect(find.textContaining('৳7,500 over'), findsOneWidget);
    expect(find.text('Recent Transactions'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Super Shop'), 200);
    expect(find.text('−৳1,250'), findsOneWidget);
  });

  testWidgets('budget renders in dark mode too', (tester) async {
    await pumpV2(
      tester,
      const Scaffold(body: BudgetScreen()),
      theme: buildTheme(brightness: Brightness.dark),
    );
    expect(find.text('Total Income'), findsOneWidget);
  });

  group('contrast', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    for (final (name, s) in [
      ('light', AppSurface.light),
      ('dark', AppSurface.dark),
    ]) {
      test('$name text tokens reach 4.5:1 on bg and card', () {
        for (final bg in [s.bg, s.card]) {
          for (final fg in [
            s.ink,
            s.inkSub,
            s.primary,
            s.positive,
            s.negative,
          ]) {
            expect(
              ratio(fg, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$name $fg on $bg',
            );
          }
        }
        expect(ratio(s.onPrimary, s.primary), greaterThanOrEqualTo(4.5));
      });
    }

    test('module icon inks reach 4.5:1 on their tiles', () {
      for (final a in Accents.all) {
        expect(ratio(a.ink, a.soft), greaterThanOrEqualTo(4.5));
        expect(ratio(a.inkDark, a.softDark), greaterThanOrEqualTo(4.5));
      }
    });
  });
}
