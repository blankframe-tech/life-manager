import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/canvas/blueprint.dart';
import 'package:life_manager/canvas/canvas_store.dart';
import 'package:life_manager/canvas/canvas_text_isar.dart';
import 'package:life_manager/canvas/shaper.dart';
import 'package:life_manager/models/canvas_text.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:life_manager/store/isar_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/isar_core.dart';
import 'package:life_manager/canvas/samples.dart';

// Stands in for the DB between "launches" within one test.
var text = CanvasTextStore();

Future<CanvasNotifier> fresh([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  return CanvasNotifier(await SharedPreferences.getInstance(), text);
}

Future<String> savedPrefs() async =>
    (await SharedPreferences.getInstance()).getString(kCanvasPrefsKey)!;

const privateNote = '''
Loan from Karim (hospital bills):
- Paid back 2000

Therapy sessions:
- Book the next one
''';

void main() {
  setUp(() => text = CanvasTextStore());

  test('prefs never hold headings, renames or file names', () async {
    final a = await fresh();
    a.commit(
      a.preview([const SourceDoc('karim-debt-and-therapy', privateNote)]),
    );
    final loan = a.state.allSections.firstWhere(
      (s) => s.title.startsWith('Loan from Karim'),
    );
    a.rename(loan.id, 'Nadia loan (secret)');

    final saved = await savedPrefs();
    for (final secret in [
      'Karim',
      'hospital',
      'Therapy',
      'karim-debt-and-therapy',
      'Nadia',
    ]) {
      expect(saved, isNot(contains(secret)), reason: secret);
    }
    expect(text.read(), contains('Therapy sessions'));

    // A relaunch puts every word back exactly.
    final b = await fresh({kCanvasPrefsKey: saved});
    expect(b.state.sources.single.name, 'karim-debt-and-therapy');
    expect(b.state.allSections, a.state.allSections);
    expect(b.state.overrides[loan.id]!.title, 'Nadia loan (secret)');
    expect(
      b.state.blueprint!.sections.toList(),
      a.state.blueprint!.sections.toList(),
    );
  });

  test(
    'a state saved by an older build moves its words out of prefs',
    () async {
      final a = await fresh();
      a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
      final old = jsonEncode(a.state.toJson());
      expect(old, contains('Dena paona'));

      text = CanvasTextStore();
      final b = await fresh({kCanvasPrefsKey: old});
      expect(b.state.allSections, a.state.allSections);
      expect(await savedPrefs(), isNot(contains('Dena paona')));
      expect(text.read(), contains('Dena paona'));
    },
  );

  test('without its words the shape still loads, as Untitled', () async {
    final a = await fresh();
    a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
    text = CanvasTextStore();
    final b = await fresh({kCanvasPrefsKey: await savedPrefs()});
    expect(b.state.active, isTrue);
    expect(b.state.allSections.map((s) => s.title).toSet(), {'Untitled'});
  });

  test('a store that fails never breaks loading or saving', () async {
    final a = await fresh();
    a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
    final saved = await savedPrefs();
    final old = jsonEncode(a.state.toJson());

    text = _BrokenText();
    final b = await fresh({kCanvasPrefsKey: saved});
    expect(b.state.active, isFalse); // unreadable words: the classic layout
    final c = await fresh({kCanvasPrefsKey: old});
    final id = c.state.allSections.first.id;
    c.rename(id, 'Still renamed');
    c.reset();
    await pumpEventQueue();
    // Nothing reached the store, so the older build's state stays as it was.
    expect(await savedPrefs(), old);
  });

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
    expect(text.read(), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(kCanvasPrefsKey),
      isNull,
    );
  });

  group('IsarCanvasText', () {
    late Isar isar;
    late Directory dir;
    // Isar runs async write transactions in order, so an empty one waits
    // for every write queued before it.
    Future<void> flush() async {
      await isar.writeTxn(() async {});
      await pumpEventQueue();
    }

    setUpAll(initIsarForTests);
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('canvas_text');
      isar = await Isar.open(
        [ItemSchema, HistoryEventSchema, CanvasTextSchema],
        directory: dir.path,
        name: 'canvas_text',
      );
    });
    tearDown(() async {
      await isar.close(deleteFromDisk: true);
      dir.deleteSync(recursive: true);
    });

    test('keeps the words in the DB across launches', () async {
      text = IsarCanvasText(isar);
      final a = await fresh();
      a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
      await flush();
      expect(isar.canvasTexts.getSync(0)!.json, contains('Dena paona'));

      final b = await fresh({kCanvasPrefsKey: await savedPrefs()});
      expect(b.state.allSections, a.state.allSections);

      b.reset();
      await flush();
      expect(isar.canvasTexts.countSync(), 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(kCanvasPrefsKey), isFalse);
    });

    test('a rename while another write runs is saved after it', () async {
      text = IsarCanvasText(isar);
      final a = await fresh();
      a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
      await flush();
      final id = a.state.allSections.first.id;

      final release = Completer<void>();
      final held = isar.writeTxn(() => release.future);
      a.rename(id, 'Renamed while busy');
      expect(a.state.overrides[id]!.title, 'Renamed while busy');

      release.complete();
      await held;
      await flush();
      expect(isar.canvasTexts.getSync(0)!.json, contains('Renamed while busy'));
      expect(await savedPrefs(), isNot(contains('Renamed while busy')));
    });

    test('an older build\'s state splits while another write runs', () async {
      text = IsarCanvasText(isar);
      final a = await fresh();
      a.commit(a.preview([const SourceDoc('Keep', keepNote)]));
      await flush();
      final old = jsonEncode(a.state.toJson());
      await isar.writeTxn(() => isar.canvasTexts.clear());

      final release = Completer<void>();
      final held = isar.writeTxn(() => release.future);
      final b = await fresh({kCanvasPrefsKey: old});
      expect(b.state.allSections, a.state.allSections);
      // The words leave prefs only once they are in the DB.
      expect(await savedPrefs(), contains('Dena paona'));

      release.complete();
      await held;
      await flush();
      expect(isar.canvasTexts.getSync(0)!.json, contains('Dena paona'));
      expect(await savedPrefs(), isNot(contains('Dena paona')));
    });
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
      final store = IsarStore(isar);
      final sync = SyncService(store);
      final items = Shaper.compile(const SourceDoc('Keep', keepNote)).items;
      expect(await writeNewItems(store, sync, items), items.length);

      final rent = await isar.items.filter().titleEqualTo('Rent').findFirst();
      rent!.title = 'Rent (new flat)';
      await sync.save(rent);
      final soap = await isar.items.filter().titleEqualTo('Soap').findFirst();
      await sync.delete(soap!);

      final again = Shaper.compile(const SourceDoc('Keep', keepNote)).items;
      expect(await writeNewItems(store, sync, again), 0);
      expect(await isar.items.filter().titleEqualTo('Rent').count(), 0);
      // By uuid: a tombstone is content-free, so its title is blank.
      final soapNow = await store.item(soap.uuid);
      expect(soapNow!.isDeleted, isTrue);
    });
  });
}

class _BrokenText extends CanvasTextStore {
  @override
  String? read() => throw StateError('db closed');
  @override
  Future<void> write(String? json) async => throw StateError('db closed');
}
