// The canvas end to end on a real Isar: shape the app from the built-in
// example, use it, edit a row. Run on a booted simulator:
//   SHOTS_DIR=/tmp/shots flutter drive --driver test_driver/integration_test.dart \
//     --target integration_test/canvas_flow_test.dart -d "iPhone 18 Pro"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/canvas/canvas_shell.dart';
import 'package:life_manager/canvas/morph_screen.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/providers/providers.dart';
import 'package:life_manager/screens/root_scaffold.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue);
    await tester.pumpAndSettle();
  }

  testWidgets('shape from the example, then use it', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_done_v2': true});
    final prefs = await SharedPreferences.getInstance();
    final dir = await getTemporaryDirectory();
    final isar = await Isar.open(
      [ItemSchema, HistoryEventSchema],
      directory: dir.path,
      name: 'canvas_flow_${DateTime.now().millisecondsSinceEpoch}',
    );
    addTearDown(() => isar.close(deleteFromDisk: true));
    final nav = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isarProvider.overrideWithValue(isar),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          navigatorKey: nav,
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const RootScaffold(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CanvasShell), findsNothing);

    nav.currentState!.push(
      MaterialPageRoute(builder: (_) => const MorphScreen()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Try an example'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('canvas-1-preview');

    await tester.tap(find.text('Shape my app'));
    await settle(tester, () => find.byType(CanvasShell).evaluate().isNotEmpty);
    await settle(tester, () => find.text('Rent').evaluate().isNotEmpty);
    await binding.takeScreenshot('canvas-2-money');

    final count = await isar.items.count();
    expect(count, greaterThan(20));

    final tabs = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byType(NavigationDestination),
    );
    final labels = [
      for (final e in tabs.evaluate())
        (e.widget as NavigationDestination).label,
    ];
    for (final (i, label) in labels.indexed.skip(1)) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('canvas-${i + 2}-$label');
    }

    // Inline add in the bazaar list keeps the price.
    await tester.tap(find.text('Shopping').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Add to Bazaar list…'),
      'Batteries 90',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester, () => find.text('Batteries').evaluate().isNotEmpty);
    final batteries = await isar.items
        .filter()
        .titleEqualTo('Batteries')
        .findFirst();
    expect(batteries!.amount, 90);
    expect(batteries.kind, ItemKind.buy);

    // Editing a row in the editor keeps it in its canvas section.
    await tester.tap(find.text('Batteries'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Batteries'),
      'AA batteries',
    );
    await tester.tap(find.text('Save changes'));
    await settle(tester, () => find.text('AA batteries').evaluate().isNotEmpty);
    final edited = await isar.items
        .filter()
        .uuidEqualTo(batteries.uuid)
        .findFirst();
    expect(edited!.section, batteries.section);
    await binding.takeScreenshot('canvas-9-after-edit');
  });
}
