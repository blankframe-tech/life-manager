import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/providers/providers.dart';
import 'package:life_manager/screens/transactions_screen.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:life_manager/widgets/item_editor.dart';
import 'package:life_manager/services/txn_category_service.dart';
import 'package:life_manager/util/week.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A transaction that happened on [on], in local time.
Item _txn(
  String title, {
  required double amount,
  required DateTime on,
  String direction = TxnDirection.spend,
  String? category,
}) =>
    Item()
      ..uuid = '$title-${on.toIso8601String()}'
      ..kind = ItemKind.txn
      ..title = title
      ..amount = amount
      ..direction = direction
      ..category = category
      ..dueDate = on
      ..updatedAt = DateTime.now().toUtc();

// 2026-08-20 is a Thursday; its week runs Mon 17th – Sun 23rd.
final _thursday = DateTime(2026, 8, 20);
final _monday = DateTime(2026, 8, 17);

void main() {
  group('startOfWeek', () {
    test('snaps back to Monday midnight', () {
      expect(startOfWeek(DateTime(2026, 8, 20, 14, 30)), _monday);
    });

    test('keeps a Monday on itself, and pulls a Sunday back six days', () {
      expect(startOfWeek(DateTime(2026, 8, 17, 0, 1)), _monday);
      // Sunday the 16th belongs to the *previous* week, not the coming one.
      expect(startOfWeek(DateTime(2026, 8, 16, 23, 59)), DateTime(2026, 8, 10));
    });
  });

  group('rollupByWeek', () {
    test('groups by week, newest first, with rows newest first inside', () {
      final weeks = rollupByWeek([
        _txn('older week', amount: 100, on: DateTime(2026, 8, 12)),
        _txn('monday', amount: 200, on: _monday),
        _txn('thursday', amount: 300, on: _thursday),
      ]);

      expect(weeks.map((w) => w.start).toList(),
          [_monday, DateTime(2026, 8, 10)]);
      expect(weeks.first.items.map((i) => i.title).toList(),
          ['thursday', 'monday']);
    });

    test('totals earnings and spending separately', () {
      final week = rollupByWeek([
        _txn('lunch', amount: 250, on: _thursday),
        _txn('bus', amount: 50, on: _monday),
        _txn('salary',
            amount: 40000, on: _monday, direction: TxnDirection.earn),
      ]).single;

      expect(week.spent, 300);
      expect(week.earned, 40000);
      expect(week.net, 39700);
    });

    test('breaks spending down by category, largest first, ignoring income',
        () {
      final week = rollupByWeek([
        _txn('lunch', amount: 250, on: _thursday, category: 'Food'),
        _txn('dinner', amount: 150, on: _monday, category: 'Food'),
        _txn('bus', amount: 50, on: _monday, category: 'Transport'),
        _txn('untagged', amount: 20, on: _monday),
        _txn('salary',
            amount: 40000,
            on: _monday,
            direction: TxnDirection.earn,
            category: 'Salary'),
      ]).single;

      expect(week.spendByCategory,
          {'Food': 400.0, 'Transport': 50.0, 'Uncategorised': 20.0});
    });

    test('an amount-less row still lands in its week without breaking totals',
        () {
      final week = rollupByWeek([
        Item()
          ..uuid = 'no-amount'
          ..kind = ItemKind.txn
          ..title = 'forgot the amount'
          ..dueDate = _thursday
          ..updatedAt = DateTime.now().toUtc(),
      ]).single;

      expect(week.items, hasLength(1));
      expect(week.spent, 0);
      expect(week.spendByCategory, isEmpty);
    });

    test('falls back to the write time when no date was recorded', () {
      final legacy = Item()
        ..uuid = 'legacy'
        ..kind = ItemKind.txn
        ..title = 'imported'
        ..amount = 10
        ..updatedAt = _thursday.toUtc();

      expect(rollupByWeek([legacy]).single.start,
          startOfWeek(_thursday.toUtc().toLocal()));
    });

    test('empty in, empty out', () {
      expect(rollupByWeek([]), isEmpty);
    });
  });

  group('weekLabel', () {
    test('names the current and previous week in words', () {
      expect(weekLabel(_monday, now: _thursday), 'This week');
      expect(weekLabel(DateTime(2026, 8, 10), now: _thursday), 'Last week');
    });

    test('older weeks get a date range', () {
      expect(weekLabel(DateTime(2026, 8, 3), now: _thursday), '3–9 Aug');
    });

    test('a range spanning two months names both', () {
      expect(weekRangeLabel(DateTime(2026, 7, 27), now: _thursday),
          '27 Jul – 2 Aug');
    });

    test('a range in another year says so', () {
      expect(weekRangeLabel(DateTime(2025, 12, 29), now: _thursday),
          '29 Dec – 4 Jan 2026');
    });
  });

  group('mergeUsedCategories', () {
    test('appends categories that are in use but no longer configured', () {
      expect(
        mergeUsedCategories(['Food', 'Bills'], ['Food', 'Rent', null, '']),
        ['Food', 'Bills', 'Rent'],
      );
    });

    test('matches case-insensitively, so a stray never duplicates a real one',
        () {
      expect(mergeUsedCategories(['Food'], ['food']), ['Food']);
    });
  });

  group('TxnCategoryNotifier', () {
    Future<TxnCategoryNotifier> notifier(
        [Map<String, Object> initial = const {}]) async {
      SharedPreferences.setMockInitialValues(initial);
      return TxnCategoryNotifier(await SharedPreferences.getInstance());
    }

    test('starts from the defaults and persists every change', () async {
      final categories = await notifier();
      expect(categories.state, kDefaultTxnCategories);

      categories.add('Rent');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('txn_categories'), contains('Rent'));

      // A fresh notifier over the same prefs sees the addition.
      final reopened =
          TxnCategoryNotifier(await SharedPreferences.getInstance());
      expect(reopened.state, contains('Rent'));
    });

    test('trims, and refuses blanks and case-insensitive duplicates', () async {
      final categories = await notifier({'txn_categories': <String>['Food']});

      expect(categories.add('  Rent '), 'Rent');
      expect(categories.add('   '), isNull);
      expect(categories.add('food'), isNull);
      expect(categories.state, ['Food', 'Rent']);
    });

    test('removing takes it out of the list only', () async {
      final categories =
          await notifier({'txn_categories': <String>['Food', 'Rent']});

      categories.remove('Food');
      expect(categories.state, ['Rent']);
      expect(categories.contains('Food'), isFalse);
    });
  });

  group('transaction round-trip', () {
    test('keeps direction, category and the date the money moved', () {
      final original = _txn('Groceries',
          amount: 1200, on: DateTime(2026, 8, 18), category: 'Food');

      final restored = Item.fromMap(original.toMap());

      expect(restored.kind, ItemKind.txn);
      expect(restored.direction, TxnDirection.spend);
      expect(restored.category, 'Food');
      expect(restored.occurredAt, DateTime(2026, 8, 18));
      expect(restored.signedAmount, -1200);
      expect(restored.isEarning, isFalse);
    });

    test('earnings count positive', () {
      final earned = _txn('Salary',
          amount: 40000,
          on: _monday,
          direction: TxnDirection.earn,
          category: 'Salary');
      expect(earned.signedAmount, 40000);
      expect(earned.isEarning, isTrue);
    });
  });

  group('TransactionsScreen', () {
    /// Renders the screen over a fixed set of transactions, with no Isar
    /// behind it — [itemsProvider] is a stream, so a stream of literals is a
    /// complete stand-in.
    Future<void> pump(WidgetTester tester, List<Item> items) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          itemsProvider(ItemKind.txn).overrideWith((ref) => Stream.value(items)),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: TransactionsScreen()),
        ),
      ));
      await tester.pump();
    }

    testWidgets('invites a first entry when there is nothing logged',
        (tester) async {
      await pump(tester, []);

      expect(find.text('No transactions'), findsOneWidget);
      expect(find.text('Add a transaction'), findsOneWidget);
    });

    testWidgets('rolls the current week up and heads each week block',
        (tester) async {
      final thisWeek = startOfWeek(DateTime.now()).add(const Duration(days: 1));
      final lastWeek = thisWeek.subtract(const Duration(days: 7));
      await pump(tester, [
        _txn('Lunch', amount: 250, on: thisWeek, category: 'Food'),
        _txn('Pay', amount: 1000, on: thisWeek, direction: TxnDirection.earn),
        _txn('Bus', amount: 50, on: lastWeek, category: 'Transport'),
      ]);

      // Summary card: this week's totals, and what's left of them.
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('৳1,000'), findsOneWidget); // earned
      expect(find.text('৳250'), findsOneWidget); // spent
      expect(find.text('Left over: +৳750'), findsOneWidget);

      // One block per week, each headed and totalled.
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('LAST WEEK'), findsOneWidget);
      expect(find.text('In ৳1,000'), findsOneWidget);
      expect(find.text('Out ৳250'), findsOneWidget);

      // Rows, signed by direction.
      expect(find.text('+৳1,000'), findsOneWidget);
      expect(find.text('−৳250'), findsOneWidget);
      // Twice: the row, and last week's net in its group header.
      expect(find.text('−৳50'), findsNWidgets(2));
      // This week's net in its group header.
      expect(find.text('+৳750'), findsOneWidget);

      // The category breakdown is labelled, never colour-only.
      expect(find.text('Food 100%'), findsWidgets);
    });

    testWidgets('the summary card opens a weekly trend breakdown',
        (tester) async {
      final thisWeek = startOfWeek(DateTime.now()).add(const Duration(days: 1));
      await pump(tester, [
        _txn('Lunch', amount: 250, on: thisWeek, category: 'Food'),
        _txn('Pay', amount: 1000, on: thisWeek, direction: TxnDirection.earn),
        _txn('Bus',
            amount: 50,
            on: thisWeek.subtract(const Duration(days: 7)),
            category: 'Transport'),
      ]);

      await tester.tap(find.text('Tap for the last 8 weeks'));
      await tester.pumpAndSettle();

      expect(find.text('Weekly trend'), findsOneWidget);
      // Both weeks listed under the chart, which is the accessible reading of
      // it — the chart itself is supplementary. "This week" twice: the
      // summary card behind the sheet still carries its own label.
      expect(find.text('This week'), findsNWidgets(2));
      expect(find.text('Last week'), findsOneWidget);
    });

    testWidgets('search matches the category, not just the title',
        (tester) async {
      final today = startOfWeek(DateTime.now()).add(const Duration(days: 1));
      final container = ProviderContainer(overrides: [
        itemsProvider(ItemKind.txn).overrideWith((ref) => Stream.value([
              _txn('Lunch', amount: 250, on: today, category: 'Food'),
              _txn('Bus', amount: 50, on: today, category: 'Transport'),
            ])),
      ]);
      addTearDown(container.dispose);
      container.read(searchQueryProvider(ItemKind.txn).notifier).state =
          'transport';

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: TransactionsScreen()),
        ),
      ));
      await tester.pump();

      expect(find.text('Bus'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
    });
  });

  group('transaction editor', () {
    Future<void> open(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showItemEditor(context, ref, ItemKind.txn),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for direction, category, amount and date',
        (tester) async {
      await open(tester);

      expect(find.text('New Transaction'), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(find.text('Earned'), findsOneWidget);
      // Categories come from the store, with a way to add one on the spot.
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Amount (৳)'), findsOneWidget);
      // Dated today by default, so the common case needs no picker.
      expect(find.textContaining('Date · '), findsOneWidget);
    });

    testWidgets('refuses to file a transaction with no amount',
        (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField).first, 'Lunch');
      // The sheet is taller than the test viewport, so the save button has to
      // be scrolled to before it can be tapped.
      await tester.ensureVisible(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Still open, with the reason on screen — nothing was saved, which
      // matters because saving would need a sync service and an Isar.
      expect(find.text('Enter an amount above zero.'), findsOneWidget);
      expect(find.text('New Transaction'), findsOneWidget);
    });

    testWidgets('adds a category from inside the sheet and selects it',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'Rent');
      // Scoped to the dialog: the editor's own save button also says "Add".
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Add'),
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Rent'), findsOneWidget);
      final chip =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Rent'));
      expect(chip.selected, isTrue,
          reason: 'a category you just created is the one you meant to use');
    });
  });
}
