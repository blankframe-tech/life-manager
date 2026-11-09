import 'history_event.dart';

/// The web build's [HistoryEvent]: the same fields as
/// `history_event_isar.dart` (see the docs there), without Isar.
class HistoryEvent {
  int id = 0; // unused: the in-memory store keys rows by uuid
  late String uuid;
  late String itemUuid;
  late String itemKind;
  String title = '';
  late String action;
  late DateTime timestamp;
  bool isSynced = false;
  HistoryEvent();

  Map<String, dynamic> toMap() => historyToMap(this);

  static HistoryEvent fromMap(Map<String, dynamic> m) => historyFromMap(m);
}
