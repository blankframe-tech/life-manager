import 'dart:async';

import '../models/history_event.dart';
import '../models/item.dart';
import 'local_store.dart';

/// [LocalStore] held only in memory — the web build's store. Filled from the
/// decrypted vault; dropping the object drops the data.
class MemoryStore implements LocalStore {
  final _items = <String, Item>{};
  final _history = <String, HistoryEvent>{};
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get changes => _changes.stream;

  /// Emits [read] now and after every change.
  Stream<T> _watch<T>(T Function() read) => Stream.multi((c) {
    c.add(read());
    final sub = _changes.stream.listen((_) => c.add(read()));
    c.onCancel = sub.cancel;
  });

  @override
  Stream<List<Item>> watchItems(String kind) => _watch(
    () =>
        _items.values
            .where((i) => i.kind == kind && !i.isDeleted)
            .map(copyItem)
            .toList()
          ..sort((a, b) {
            final s = a.sortOrder.compareTo(b.sortOrder);
            return s != 0 ? s : b.updatedAt.compareTo(a.updatedAt);
          }),
  );

  @override
  Stream<List<HistoryEvent>> watchHistory() =>
      _watch(() => _historySorted().reversed.toList());

  List<HistoryEvent> _historySorted() =>
      _history.values.map(_copyEvent).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<List<Item>> items({bool? synced}) async => [
    for (final i in _items.values)
      if (synced == null || i.isSynced == synced) copyItem(i),
  ];

  @override
  Future<List<HistoryEvent>> history({bool? synced}) async => [
    for (final h in _historySorted())
      if (synced == null || h.isSynced == synced) h,
  ];

  @override
  Future<Item?> item(String uuid) async {
    final i = _items[uuid];
    return i == null ? null : copyItem(i);
  }

  @override
  Future<void> putItems(Iterable<Item> items) async {
    for (final i in items) {
      _items[i.uuid] = copyItem(i);
    }
    _changes.add(null);
  }

  @override
  Future<void> putHistory(Iterable<HistoryEvent> events) async {
    for (final h in events) {
      _history[h.uuid] = _copyEvent(h);
    }
    _changes.add(null);
  }

  @override
  Future<void> clear() async {
    _items.clear();
    _history.clear();
    _changes.add(null);
  }

  /// Drops every row and closes the change stream. The store is unusable after.
  void dispose() {
    _items.clear();
    _history.clear();
    _changes.close();
  }

  static HistoryEvent _copyEvent(HistoryEvent h) =>
      HistoryEvent.fromMap(h.toMap())
        ..id = h.id
        ..isSynced = h.isSynced;
}
