import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/canvas/blueprint.dart';
import 'package:life_manager/canvas/canvas_shell.dart';
import 'package:life_manager/canvas/canvas_store.dart';
import 'package:life_manager/canvas/morph_screen.dart';
import 'package:life_manager/canvas/samples.dart';
import 'package:life_manager/canvas/shaper.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/screens/root_scaffold.dart';

import '../v2_helpers.dart';

/// Prefs holding a committed canvas built from [docs], and its rows.
(Map<String, Object>, List<Item>) canvasFrom(List<SourceDoc> docs) {
  final sources = [
    for (final (i, d) in docs.indexed)
      Shaper.compile(d, orderBase: i * kOrderStride),
  ];
  final state = CanvasState(
    sources: sources,
    blueprint: layout([for (final s in sources) ...s.sections]),
  );
  return (
    {kCanvasPrefsKey: jsonEncode(state.toJson())},
    [for (final s in sources) ...s.items],
  );
}

Finder navLabel(String text) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(text));

void main() {
  testWidgets('without a canvas the shell is the classic module layout', (
    tester,
  ) async {
    await pumpV2(tester, const RootScaffold());
    expect(find.byType(CanvasShell), findsNothing);
    expect(navLabel('Budget'), findsOneWidget);
  });

  testWidgets('a small shape is one page with no bottom nav', (tester) async {
    final (prefs, items) = canvasFrom([
      const SourceDoc(
        'Keep',
        'Bazaar list\n- Eggs 150\n- [x] Soap\n\nTODO\n- Call the bank',
      ),
    ]);
    await pumpV2(tester, const RootScaffold(), prefs: prefs, items: items);

    expect(find.byType(CanvasShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('BAZAAR LIST'), findsOneWidget);
    expect(find.text('Eggs'), findsOneWidget);
    expect(find.text('1 left · ৳150'), findsOneWidget);
    expect(find.text('Call the bank'), findsOneWidget);
    expect(find.text('Jot anything — it finds its place'), findsOneWidget);
  });

  testWidgets('a big shape gets tabs, and each tab shows its sections', (
    tester,
  ) async {
    final (prefs, items) = canvasFrom(kSampleSources);
    await pumpV2(tester, const RootScaffold(), prefs: prefs, items: items);

    final bp = layout([
      for (final (i, d) in kSampleSources.indexed)
        ...Shaper.compile(d, orderBase: i * kOrderStride).sections,
    ]);
    expect(bp.tabs.length, inInclusiveRange(2, kMaxTabs));
    for (final t in bp.tabs) {
      expect(navLabel(t.title), findsOneWidget);
    }

    await tester.tap(navLabel('People'));
    await tester.pumpAndSettle();
    expect(find.text('Rahim'), findsOneWidget);
    expect(find.text('owed ৳1,000'), findsOneWidget); // 500 + 2000 − 300 − 1200
  });

  testWidgets('hiding a section removes it and offers it back', (tester) async {
    final (prefs, items) = canvasFrom([
      const SourceDoc('Keep', 'Bazaar list\n- Eggs\n\nTODO\n- Call the bank'),
    ]);
    await pumpV2(tester, const RootScaffold(), prefs: prefs, items: items);

    await tester.tap(find.byTooltip('Options for TODO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(find.text('TODO'), findsNothing);
    expect(find.text('Call the bank'), findsNothing);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show 1 hidden section'));
    await tester.pumpAndSettle();
    expect(find.text('TODO'), findsOneWidget);
  });

  testWidgets('the import screen previews the shape before saving', (
    tester,
  ) async {
    // Tall enough that the preview below the paste box is laid out.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpV2(tester, const MorphScreen());
    final shape = find.widgetWithText(FilledButton, 'Shape my app');
    expect(tester.widget<FilledButton>(shape).onPressed, isNull);

    await tester.enterText(
      find.byType(TextField),
      'Dena paona\nRahim owes me 500\n\nBazaar\n- eggs',
    );
    await tester.tap(find.text('Add this text'));
    await tester.pumpAndSettle();

    expect(find.text('Pasted note'), findsOneWidget);
    expect(
      find.text('One page, no tabs — like a single pinned note.'),
      findsOneWidget,
    );
    expect(find.text('Dena paona · who owes whom · 1 new'), findsOneWidget);
    expect(tester.widget<FilledButton>(shape).onPressed, isNotNull);

    await tester.tap(find.text('Try an example'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tabs: '), findsOneWidget);
  });
}
