import '../models/history_event.dart';
import '../models/item.dart';

/// The one place the app reads and writes its rows.
///
/// iOS / Android use [IsarStore] (`isar_store.dart`), the on-device database.
/// The web build uses [MemoryStore] (`memory_store.dart`), filled from the
/// decrypted vault and dropped on lock: nothing is persisted in the browser.
///
/// Rows handed out are detached copies, as Isar's are: mutating one changes
/// nothing until it is passed back to [putItems].
abstract class LocalStore {
  /// Live (non-deleted) items of [kind], by `sortOrder`, then newest first.
  /// Emits immediately, then after every change.
  Stream<List<Item>> watchItems(String kind);

  /// Every history event, newest first. Emits immediately.
  Stream<List<HistoryEvent>> watchHistory();

  /// Fires after any write to items or history.
  Stream<void> get changes;

  /// Every item, tombstones included. [synced] filters on `isSynced`.
  Future<List<Item>> items({bool? synced});

  /// Every history event, oldest first. [synced] filters on `isSynced`.
  Future<List<HistoryEvent>> history({bool? synced});

  Future<Item?> item(String uuid);

  /// Inserts or replaces by `uuid`, in one transaction.
  Future<void> putItems(Iterable<Item> items);

  /// Inserts or replaces by `uuid`, in one transaction.
  Future<void> putHistory(Iterable<HistoryEvent> events);

  /// Removes every item and history event.
  Future<void> clear();
}
