import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/backup_service.dart';

/// Builds the JSON a backup file would contain, without needing an Isar
/// instance — the merge/validation logic under test is all in [BackupService],
/// and the file shape is just each model's `toMap()`.
String backupJson({
  List<Item> items = const [],
  List<HistoryEvent> history = const [],
  String format = BackupService.formatName,
  int version = BackupService.formatVersion,
}) =>
    jsonEncode({
      'format': format,
      'version': version,
      'exportedAt': DateTime.utc(2026, 8, 12, 9, 30).toIso8601String(),
      'items': items.map((i) => i.toMap()).toList(),
      'history': history.map((h) => h.toMap()).toList(),
    });

Item item(String uuid, {String title = 'Rent', DateTime? updatedAt}) => Item()
  ..uuid = uuid
  ..kind = ItemKind.budget
  ..title = title
  ..category = BudgetCategory.needs
  ..amount = 12000
  ..updatedAt = updatedAt ?? DateTime.utc(2026, 8, 1);

HistoryEvent event(String uuid) => HistoryEvent()
  ..uuid = uuid
  ..itemUuid = 'item-1'
  ..itemKind = ItemKind.budget
  ..title = 'Rent'
  ..action = HistoryAction.created
  ..timestamp = DateTime.utc(2026, 8, 1);

void main() {
  // `peek` and the validation it shares with `importJson` need no database.
  final service = BackupService(_NoDb());

  group('peek', () {
    test('reports what a backup holds', () {
      final summary = service.peek(backupJson(
        items: [item('a'), item('b')],
        history: [event('h1')],
      ));

      expect(summary.items, 2);
      expect(summary.history, 1);
      expect(summary.exportedAt?.toUtc(), DateTime.utc(2026, 8, 12, 9, 30));
    });

    test('rejects a file that is not JSON', () {
      expect(
        () => service.peek('not json at all'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects JSON that is not one of our backups', () {
      expect(
        () => service.peek(jsonEncode({'hello': 'world'})),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => service.peek(backupJson(format: 'something-else')),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('refuses a format version this build cannot read', () {
      expect(
        () => service.peek(backupJson(version: BackupService.formatVersion + 1)),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('accepts an older format version', () {
      expect(service.peek(backupJson(version: 1)).items, 0);
    });

    test('error messages are safe to show as-is', () {
      try {
        service.peek('{');
        fail('should have thrown');
      } on BackupFormatException catch (e) {
        expect(e.message, isNotEmpty);
        // No stack traces, no library internals leaking into the UI.
        expect(e.message.toLowerCase(), isNot(contains('exception')));
        expect(e.toString(), e.message);
      }
    });
  });

  group('round trip', () {
    test('an item survives toMap -> JSON -> fromMap unchanged', () {
      final original = item('a', title: 'Groceries')
        ..note = 'weekly'
        ..done = true
        ..sortOrder = 4
        ..dueDate = DateTime.utc(2026, 9, 1)
        ..isDeleted = true;

      final decoded = jsonDecode(backupJson(items: [original]));
      final restored = Item.fromMap(
          Map<String, dynamic>.from((decoded['items'] as List).first as Map));

      expect(restored.uuid, original.uuid);
      expect(restored.title, 'Groceries');
      expect(restored.note, 'weekly');
      expect(restored.amount, original.amount);
      expect(restored.category, original.category);
      expect(restored.done, isTrue);
      expect(restored.sortOrder, 4);
      expect(restored.dueDate?.toUtc(), DateTime.utc(2026, 9, 1));
      expect(restored.updatedAt.toUtc(), original.updatedAt.toUtc());
      // Tombstones must survive, or deleted items come back on import.
      expect(restored.isDeleted, isTrue);
    });

    test('a history event survives the round trip', () {
      final decoded = jsonDecode(backupJson(history: [event('h1')]));
      final restored = HistoryEvent.fromMap(
          Map<String, dynamic>.from((decoded['history'] as List).first as Map));

      expect(restored.uuid, 'h1');
      expect(restored.itemUuid, 'item-1');
      expect(restored.action, HistoryAction.created);
      expect(restored.timestamp.toUtc(), DateTime.utc(2026, 8, 1));
    });
  });

  group('ImportReport', () {
    test('says so plainly when nothing changed', () {
      const report = ImportReport(
          itemsAdded: 0,
          itemsUpdated: 0,
          itemsSkipped: 9,
          historyAdded: 0,
          malformed: 0);

      expect(report.changedAnything, isFalse);
      expect(report.summary, contains('Nothing to import'));
    });

    test('counts what it did', () {
      const report = ImportReport(
          itemsAdded: 3,
          itemsUpdated: 1,
          itemsSkipped: 2,
          historyAdded: 7,
          malformed: 1);

      expect(report.changedAnything, isTrue);
      expect(report.summary, contains('3 added'));
      expect(report.summary, contains('1 updated'));
      expect(report.summary, contains('7 history entries'));
      expect(report.summary, contains('1 unreadable'));
    });

    test('unreadable rows are reported even when nothing imported', () {
      const report = ImportReport(
          itemsAdded: 0,
          itemsUpdated: 0,
          itemsSkipped: 0,
          historyAdded: 0,
          malformed: 4);

      expect(report.summary, contains('4 unreadable'));
    });
  });
}

/// `peek`/validation never touches the database, so the tests above don't need
/// a real Isar. Any accidental DB use in those paths shows up as a crash here
/// rather than passing silently.
class _NoDb implements Isar {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('peek must not touch the database');
}
