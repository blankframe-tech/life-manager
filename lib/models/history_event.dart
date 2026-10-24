// Two definitions with identical fields, like `Item`: see item.dart.
import 'history_event_isar.dart'
    if (dart.library.js_interop) 'history_event_web.dart';

export 'history_event_isar.dart'
    if (dart.library.js_interop) 'history_event_web.dart';

/// One of `created`, `edited`, `completed`, `uncompleted`, `deleted`.
class HistoryAction {
  static const created = 'created';
  static const edited = 'edited';
  static const completed = 'completed';
  static const uncompleted = 'uncompleted';
  static const deleted = 'deleted';
}

Map<String, dynamic> historyToMap(HistoryEvent h) => {
  'uuid': h.uuid,
  'item_uuid': h.itemUuid,
  'item_kind': h.itemKind,
  'title': h.title,
  'action': h.action,
  'timestamp': h.timestamp.toUtc().toIso8601String(),
};

HistoryEvent historyFromMap(Map<String, dynamic> m) => HistoryEvent()
  ..uuid = m['uuid'] as String
  ..itemUuid = m['item_uuid'] as String
  ..itemKind = m['item_kind'] as String
  ..title = (m['title'] ?? '') as String
  ..action = m['action'] as String
  ..timestamp = DateTime.parse(m['timestamp'] as String).toLocal()
  ..isSynced = true;
