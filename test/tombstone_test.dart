import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/backup_service.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:life_manager/store/memory_store.dart';

/// A deleted entry must not live on in exports, vault files or the activity
/// log: the tombstone keeps only what sync needs to propagate the deletion.
void main() {
  Item loan() => Item()
    ..uuid = 'loan'
    ..kind = ItemKind.deal
    ..title = 'Loan to Rahim'
    ..note = 'paid back in cash'
    ..amount = 50000
    ..direction = DealDirection.theyOweMe
    ..category = 'family'
    ..section = 'personal'
    ..dueDate = DateTime.utc(2026, 12, 1)
    ..updatedAt = DateTime.utc(2026, 10, 1);

  test('delete keeps a minimal tombstone and scrubs history', () async {
    final store = MemoryStore();
    final sync = SyncService(store);
    addTearDown(sync.dispose);

    await sync.save(loan());
    await sync.save((await store.item('loan'))!..note = 'edited note');
    final shown = (await store.item('loan'))!;
    await sync.delete(shown);

    final json = jsonDecode(await BackupService(store).buildJson()) as Map;
    final row = (json['items'] as List).single as Map;
    expect(row['uuid'], 'loan');
    expect(row['kind'], ItemKind.deal);
    expect(row['is_deleted'], isTrue);
    expect(row['title'], '');
    expect(row['note'], '');
    expect(row['amount'], isNull);
    expect(row['direction'], isNull);
    expect(row['category'], isNull);
    expect(row['section'], isNull);
    expect(row['due_date'], isNull);
    expect(jsonEncode(json), isNot(contains('Rahim')));
    expect(jsonEncode(json), isNot(contains('paid back')));
    expect(jsonEncode(json), isNot(contains('edited note')));

    final history = await store.history();
    expect([for (final h in history) h.action], [
      HistoryAction.created,
      HistoryAction.edited,
      HistoryAction.deleted,
    ]);
    expect([for (final h in history) h.title], everyElement(isEmpty));
  });

  test('Undo restores the full row from the copy the caller holds', () async {
    final store = MemoryStore();
    final sync = SyncService(store);
    addTearDown(sync.dispose);
    await sync.save(loan());

    // Same steps as DeletableRow: delete, then Undo with the same object.
    final shown = (await store.item('loan'))!;
    await sync.delete(shown);
    shown.isDeleted = false;
    await sync.save(shown);

    final back = (await store.item('loan'))!;
    expect(back.isDeleted, isFalse);
    expect(back.title, 'Loan to Rahim');
    expect(back.note, 'paid back in cash');
    expect(back.amount, 50000);
    expect(back.direction, DealDirection.theyOweMe);
    expect(back.dueDate, isNotNull);
  });
}
