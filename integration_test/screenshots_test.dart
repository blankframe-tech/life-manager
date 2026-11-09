// Store-style screenshots of the V2 UI over demo data (no Isar, no personal
// data). Run on a booted simulator:
//   SHOTS_DIR=/tmp/shots flutter drive --driver test_driver/integration_test.dart \
//     --target integration_test/screenshots_test.dart -d "iPhone 18 Pro"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:life_manager/app_modules.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/providers/providers.dart';
import 'package:life_manager/screens/onboarding_screen.dart';
import 'package:life_manager/screens/root_scaffold.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Item _i(
  String kind,
  String title, {
  double? amount,
  String? section,
  String? category,
  String? dir,
  DateTime? due,
  String note = '',
}) => Item()
  ..uuid = '$kind-$title'
  ..kind = kind
  ..title = title
  ..note = note
  ..amount = amount
  ..section = section
  ..category = category
  ..direction = dir
  ..dueDate = due
  ..updatedAt = DateTime.now().toUtc();

List<Item> _demo() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return [
    _i(ItemKind.budget, 'Rent', amount: 22000, category: BudgetCategory.needs),
    _i(
      ItemKind.budget,
      'Groceries',
      amount: 8000,
      category: BudgetCategory.needs,
    ),
    _i(
      ItemKind.budget,
      'Utilities',
      amount: 2500,
      category: BudgetCategory.needs,
    ),
    _i(
      ItemKind.budget,
      'Emergency fund',
      amount: 10000,
      category: BudgetCategory.savings,
    ),
    _i(
      ItemKind.budget,
      'Eating out',
      amount: 4000,
      category: BudgetCategory.wants,
    ),
    _i(ItemKind.task, 'Guitar practice', section: 'time', due: today),
    _i(
      ItemKind.task,
      'Software update',
      section: 'admin',
      due: today.add(const Duration(days: 1)),
    ),
    _i(
      ItemKind.task,
      'Donate old clothes',
      section: 'declutter',
      due: today.add(const Duration(days: 4)),
    ),
    _i(
      ItemKind.txn,
      'Super Shop',
      amount: 1250,
      category: 'Groceries',
      dir: TxnDirection.spend,
      due: today,
    ),
    _i(
      ItemKind.txn,
      'Savings transfer',
      amount: 10000,
      category: 'Savings',
      dir: TxnDirection.spend,
      due: today.subtract(const Duration(days: 1)),
    ),
    _i(
      ItemKind.txn,
      'Streaming',
      amount: 800,
      category: 'Fun',
      dir: TxnDirection.spend,
      due: today.subtract(const Duration(days: 2)),
    ),
    _i(
      ItemKind.deal,
      'Rafi — lunch money',
      amount: 1500,
      dir: DealDirection.theyOweMe,
    ),
    _i(
      ItemKind.note,
      'Weekend plan',
      note:
          'Farmers market, call grandma, '
          'finish the book.',
    ),
  ];
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> boot(
    WidgetTester tester, {
    required bool onboarded,
    ThemeMode mode = ThemeMode.light,
    List<String> introsSeen = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_done_v2': onboarded,
      'user_name': 'Sam',
      'monthly_salary': 50000.0,
      'module_intros_seen': introsSeen,
    });
    final prefs = await SharedPreferences.getInstance();
    final items = _demo();
    final kinds = {
      for (final m in kAppConfig.modules) ...m.items.map((s) => s.kind),
    };
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          for (final k in kinds)
            itemsProvider(k).overrideWith(
              (ref) => Stream.value(items.where((i) => i.kind == k).toList()),
            ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          darkTheme: buildTheme(brightness: Brightness.dark),
          themeMode: mode,
          home: const OnboardingGate(child: RootScaffold()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    await binding.takeScreenshot(name);
  }

  const allSeen = [
    'budget',
    'dealings',
    'tasks',
    'notes',
    'transactions',
    'buy',
    'dreams',
  ];

  testWidgets('screenshots', (tester) async {
    await boot(tester, onboarded: false);
    await shot(tester, '1-onboarding');

    await boot(tester, onboarded: true, introsSeen: allSeen);
    await shot(tester, '2-home');

    await tester.tap(find.text('Budget').last);
    await tester.pumpAndSettle();
    await shot(tester, '3-budget');

    await boot(
      tester,
      onboarded: true,
      introsSeen: allSeen.where((id) => id != 'tasks').toList(),
    );
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await shot(tester, '4-tasks-intro');

    await boot(
      tester,
      onboarded: true,
      introsSeen: allSeen,
      mode: ThemeMode.dark,
    );
    await shot(tester, '5-home-dark');
    await tester.tap(find.text('Budget').last);
    await tester.pumpAndSettle();
    await shot(tester, '6-budget-dark');
  });
}
