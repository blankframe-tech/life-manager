import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/local_db.dart';

import 'support/isar_core.dart';

void main() {
  late Directory docs, support;

  setUpAll(initIsarForTests);
  setUp(() {
    final root = Directory.systemTemp.createTempSync('local_db');
    docs = Directory('${root.path}/Documents')..createSync();
    support = Directory('${root.path}/Library/Application Support');
  });
  tearDown(() => docs.parent.deleteSync(recursive: true));

  test('the database lives in Application Support, not Documents', () async {
    final isar = await openLocalDb(documents: docs, support: support);
    addTearDown(isar.close);
    expect(isar.path, startsWith(support.path));
    expect(isar.path, isNot(startsWith(docs.path)));
    expect(docs.listSync(), isEmpty);
  });

  test('migrates a pre-V2 database out of Documents, keeping its rows',
      () async {
    final old = await Isar.open([ItemSchema, HistoryEventSchema],
        directory: docs.path);
    await old.writeTxn(() => old.items.put(Item()
      ..uuid = 'u1'
      ..kind = ItemKind.task
      ..title = 'kept'
      ..updatedAt = DateTime.utc(2026, 10, 1)));
    await old.close();
    expect(File('${docs.path}/default.isar').existsSync(), isTrue);

    final isar = await openLocalDb(documents: docs, support: support);
    addTearDown(isar.close);
    expect(isar.path, startsWith(support.path));
    expect((await isar.items.where().findAll()).single.title, 'kept');
    expect(docs.listSync().map((e) => e.path), isEmpty);
  });
}
