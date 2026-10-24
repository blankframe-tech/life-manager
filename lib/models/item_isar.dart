import 'package:isar_community/isar.dart';

import 'item.dart';

part 'item_isar.g.dart';

/// A single unified record. Every screen is a filtered view over this one
/// collection, and the whole collection maps to one Supabase table — which
/// keeps both local reads and cloud sync trivially simple and fast.
@collection
class Item {
  /// Local Isar primary key.
  Id id = Isar.autoIncrement;

  /// Globally-unique id shared with Supabase so records reconcile across
  /// devices without integer collisions.
  @Index(unique: true, replace: true)
  late String uuid;

  /// One of [ItemKind].
  @Index()
  late String kind;

  late String title;

  /// Freeform detail — preserves the user's original shorthand verbatim.
  String note = '';

  /// Money value in BDT (nullable — tasks/dreams have none).
  double? amount;

  /// For deals: one of [DealDirection]. For transactions: one of
  /// [TxnDirection].
  String? direction;

  /// For budget rows: one of [BudgetCategory]. For transactions: a free-form
  /// category name the user can add and remove (see `TxnCategoryNotifier`) —
  /// stored as text, not an id, so a category that gets deleted leaves the
  /// transactions that used it still readable.
  String? category;

  /// Sub-grouping within a screen:
  ///  - task: 'time' | 'admin' | 'declutter'
  ///  - buy:  'p0'   | 'wishlist'
  String? section;

  /// Task completed / item bought / deal settled.
  bool done = false;

  /// Optional deadline (tasks), and the date the money moved (transactions —
  /// read it through [TxnFields.occurredAt] rather than here). Both are "the
  /// one date this row is about", so they share a column instead of adding a
  /// second nullable timestamp to every row and a Supabase migration to a
  /// table that already has one.
  DateTime? dueDate;

  /// Manual ordering within a section (lower = higher up).
  int sortOrder = 0;

  /// Last mutation time (UTC). Drives last-write-wins conflict resolution.
  @Index()
  late DateTime updatedAt;

  /// False when local changes still need to be pushed to the cloud.
  @Index()
  bool isSynced = false;

  /// Soft delete — synced as a tombstone so deletions propagate across devices.
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
