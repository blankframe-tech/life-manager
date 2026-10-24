import 'package:isar_community/isar.dart';

import '../models/history_event.dart';
import '../models/item.dart';
import 'local_store.dart';

/// [LocalStore] over the on-device Isar database (iOS / Android).
class IsarStore implements LocalStore {
  IsarStore(this.isar);

  final Isar isar;

  @override
  Stream<List<Item>> watchItems(String kind) => isar.items
      .filter()
      .kindEqualTo(kind)
      .isDeletedEqualTo(false)
      .sortBySortOrder()
      .thenByUpdatedAtDesc()
      .watch(fireImmediately: true);

  @override
  Stream<List<HistoryEvent>> watchHistory() => isar.historyEvents
      .where()
      .sortByTimestampDesc()
      .watch(fireImmediately: true);

  @override
  Stream<void> get changes {
    final items = isar.items.watchLazy();
    final history = isar.historyEvents.watchLazy();
    return Stream.multi((c) {
      final a = items.listen(c.add);
      final b = history.listen(c.add);
      c.onCancel = () => Future.wait([a.cancel(), b.cancel()]);
    });
  }

  @override
  Future<List<Item>> items({bool? synced}) => synced == null
      ? isar.items.where().findAll()
      : isar.items.filter().isSyncedEqualTo(synced).findAll();

  @override
  Future<List<HistoryEvent>> history({bool? synced}) => synced == null
      ? isar.historyEvents.where().sortByTimestamp().findAll()
      : isar.historyEvents
            .filter()
            .isSyncedEqualTo(synced)
            .sortByTimestamp()
            .findAll();

  @override
  Future<Item?> item(String uuid) =>
      isar.items.filter().uuidEqualTo(uuid).findFirst();

  @override
  Future<void> putItems(Iterable<Item> items) =>
      isar.writeTxn(() => isar.items.putAll(items.toList()));

  @override
  Future<void> putHistory(Iterable<HistoryEvent> events) =>
      isar.writeTxn(() => isar.historyEvents.putAll(events.toList()));

  @override
  Future<void> clear() => isar.writeTxn(() => isar.clear());
}
