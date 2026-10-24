import 'package:isar_community/isar.dart';

import 'history_event.dart';

part 'history_event_isar.g.dart';

/// Append-only log of every add/edit/complete/delete across all item kinds.
/// Written by [SyncService] alongside each mutation, never edited in place —
/// there's no `isDeleted`/update path, only inserts.
@collection
class HistoryEvent {
  /// Local Isar primary key.
  Id id = Isar.autoIncrement;

  /// Globally-unique id shared with Supabase.
  @Index(unique: true, replace: true)
  late String uuid;

  /// uuid of the [Item] this event is about.
  @Index()
  late String itemUuid;

  /// One of [ItemKind] — copied at event time so the log stays readable even
  /// after the item itself is edited or deleted.
  late String itemKind;

  /// Item title snapshot at the time of this action.
  String title = '';

  /// One of [HistoryAction].
  @Index()
  late String action;

  /// When this action happened (UTC).
  @Index()
  late DateTime timestamp;

  /// False when local changes still need to be pushed to the cloud.
  @Index()
  bool isSynced = false;

  HistoryEvent();

  Map<String, dynamic> toMap() => historyToMap(this);

  static HistoryEvent fromMap(Map<String, dynamic> m) => historyFromMap(m);
}
