import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/canvas/blueprint.dart';
import 'package:life_manager/canvas/canvas_store.dart';
import 'package:life_manager/canvas/shaper.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/isar_core.dart';
import 'fixtures.dart';

Future<CanvasNotifier> fresh([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return CanvasNotifier(await SharedPreferences.getInstance());
}

void main() {
  test('starts inactive: the classic layout', () async {
    final n = await fresh();
    expect(n.state.active, isFalse);
  });

  test('preview saves nothing; commit saves and activates', () async {
    final n = await fresh();
    final p = n.preview([const SourceDoc('Keep', keepNote)]);
    expect(p.fresh.single.sections, hasLength(6));
    expect(p.items, isNotEmpty);
    expect(n.state.active, isFalse);

    n.commit(p);
    expect(n.state.active, isTrue);
    expect(n.state.blueprint!.hasNav, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kCanvasPrefsKey), isNotNull);
  });

  test('a relaunch reads the saved blueprint without re-shaping', () async {
    final a = await fresh();
    a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
    final saved = (await SharedPreferences.getInstance()).getString(
      kCanvasPrefsKey,
    )!;
    // The saved state holds sections, never the note's text.
    expect(saved, isNot(contains('Rahim owes me')));

    final b = await fresh({kCanvasPrefsKey: saved});
    expect(
      b.state.blueprint!.sections.toList(),
      a.state.blueprint!.sections.toList(),
    );
  });

  test('the same text twice is recognised, a new one is added after', () async {
    final n = await fresh();
    n.commit(n.preview([const SourceDoc('Keep', keepNote)]));
    final again = n.preview([
      const SourceDoc('Keep again', '$keepNote\n\n'),
      const SourceDoc('Budget.csv', budgetCsv),
    ]);
    expect(again.alreadyIn, 1);
    expect(again.fresh.single.name, 'Budget');
    expect(again.fresh.single.sections.single.order, kOrderStride);
    n.commit(again);
    expect(n.state.sources, hasLength(2));
  });

  test('an empty source does not switch the app to an empty canvas', () async {
    final n = await fresh();
    n.commit(n.preview([const SourceDoc('blank', '  ')]));
    expect(n.state.active, isFalse);
  });

  test('rename, hide, move and unhide re-layout and persist', () async {
    final n = await fresh();
    n.commit(n.preview([const SourceDoc('Keep', keepNote)]));
    final todo = n.state.allSections.firstWhere((s) => s.title == 'TODO');
    final dreams = n.state.allSections.firstWhere((s) => s.title == 'Dreams');

    n.rename(todo.id, 'This week');
    n.hide(dreams.id);
    expect(
      n.state.blueprint!.sections.map((s) => s.title),
      contains('This week'),
    );
    expect(
      n.state.blueprint!.sections.map((s) => s.id),
      isNot(contains(dreams.id)),
    );
    expect(n.state.hiddenSections.single.id, dreams.id);

    n.moveTo(todo.id, Domain.money);
    final money = n.state.blueprint!.tabs.firstWhere(
      (t) => t.domain == Domain.money,
    );
    expect(money.sections.map((s) => s.id), contains(todo.id));

    final reloaded = await fresh({
      kCanvasPrefsKey: (await SharedPreferences.getInstance()).getString(
        kCanvasPrefsKey,
      )!,
    });
    expect(reloaded.state.overrides[todo.id]!.title, 'This week');

    n.unhideAll();
    expect(n.state.hiddenSections, isEmpty);
    expect(n.state.overrides[todo.id]!.title, 'This week');
  });

  test('a corrupt saved state falls back to the classic layout', () async {
    final n = await fresh({kCanvasPrefsKey: '{not json'});
    expect(n.state.active, isFalse);
  });

  test('an unreadable blueprint is rebuilt from the saved sections', () async {
    final a = await fresh();
    a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
    final j =
        jsonDecode(
              (await SharedPreferences.getInstance()).getString(
                kCanvasPrefsKey,
              )!,
            )
            as Map;
    j['blueprint'] = {'format': 'garbage'};
    final b = await fresh({kCanvasPrefsKey: jsonEncode(j)});
    expect(b.state.active, isTrue);
    expect(b.state.blueprint!.sections, hasLength(6));
  });

  test('reset forgets the shape only', () async {
    final n = await fresh();
    n.commit(n.preview([const SourceDoc('Keep', keepNote)]));
    n.reset();
    expect(n.state.active, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(kCanvasPrefsKey),
      isNull,
    );
  });

  group('writeNewItems', () {
    late Isar isar;
    late Directory dir;
    setUpAll(initIsarForTests);
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('canvas_items');
      isar = await Isar.open(
        [ItemSchema, HistoryEventSchema],
        directory: dir.path,
        name: 'canvas',
      );
    });
    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    test('writes once; a re-import leaves edits and deletes alone', () async {
      final sync = SyncService(isar);
      final items = Shaper.compile(const SourceDoc('Keep', keepNote)).items;
      expect(await writeNewItems(isar, sync, items), items.length);

      final rent = await isar.items.filter().titleEqualTo('Rent').findFirst();
      rent!.title = 'Rent (new flat)';
      await sync.save(rent);
      final soap = await isar.items.filter().titleEqualTo('Soap').findFirst();
      await sync.delete(soap!);

      final again = Shaper.compile(const SourceDoc('Keep', keepNote)).items;
      expect(await writeNewItems(isar, sync, again), 0);
      expect(await isar.items.filter().titleEqualTo('Rent').count(), 0);
      final soapNow = await isar.items
          .filter()
          .titleEqualTo('Soap')
          .findFirst();
      expect(soapNow!.isDeleted, isTrue);
    });
  });
}
