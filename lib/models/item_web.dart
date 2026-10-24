import 'item.dart';

/// The web build's [Item]: the same fields as `item_isar.dart` (see the docs
/// there), without Isar. See the note at the top of item.dart.
class Item {
  int id = 0; // unused: the in-memory store keys rows by uuid
  late String uuid;
  late String kind;
  late String title;
  String note = '';
  double? amount;
  String? direction;
  String? category;
  String? section;
  bool done = false;
  DateTime? dueDate;
  int sortOrder = 0;
  late DateTime updatedAt;
  bool isSynced = false;
  bool isDeleted = false;
  Item();

  /// Serialise for Supabase (snake_case columns).
  Map<String, dynamic> toMap() => itemToMap(this);

  /// Build from a Supabase row.
  static Item fromMap(Map<String, dynamic> m) => itemFromMap(m);

  /// Build from a seed JSON object (local bootstrap data).
  static Item fromSeed(Map<String, dynamic> m, String uuid) =>
      itemFromSeed(m, uuid);
}
