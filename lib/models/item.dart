import 'package:isar_community/isar.dart';

part 'item.g.dart';

/// The five sections of the app. Stored as [Item.kind] (a String) so that the
/// value maps 1:1 onto the Supabase `items.kind` text column without depending
/// on enum ordinal stability.
class ItemKind {
  static const deal = 'deal'; // Dena Paona ledger
  static const budget = 'budget'; // 65/20/15 monthly plan
  static const task = 'task'; // to-dos
  static const buy = 'buy'; // shopping lists
  static const dream = 'dream'; // long-term wishes

  static const all = [deal, budget, task, buy, dream];
}

/// Direction of a [ItemKind.deal] entry.
class DealDirection {
  static const theyOweMe = 'they_owe'; // a credit to me (+)
  static const iOweThem = 'i_owe'; // a debt of mine (-)
}

/// Budget bucket for [ItemKind.budget] entries.
class BudgetCategory {
  static const needs = 'needs';
  static const wants = 'wants';
  static const savings = 'savings'; // savings / debt clear
}

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

  /// For deals: one of [DealDirection].
  String? direction;

  /// For budget rows: one of [BudgetCategory].
  String? category;

  /// Sub-grouping within a screen:
  ///  - task: 'time' | 'admin' | 'declutter'
  ///  - buy:  'p0'   | 'wishlist'
  String? section;

  /// Task completed / item bought / deal settled.
  bool done = false;

  /// Optional deadline (tasks).
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
  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'kind': kind,
        'title': title,
        'note': note,
        'amount': amount,
        'direction': direction,
        'category': category,
        'section': section,
        'done': done,
        'due_date': dueDate?.toUtc().toIso8601String(),
        'sort_order': sortOrder,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'is_deleted': isDeleted,
      };

  /// Build from a Supabase row.
  static Item fromMap(Map<String, dynamic> m) {
    final due = m['due_date'];
    return Item()
      ..uuid = m['uuid'] as String
      ..kind = m['kind'] as String
      ..title = (m['title'] ?? '') as String
      ..note = (m['note'] ?? '') as String
      ..amount = (m['amount'] as num?)?.toDouble()
      ..direction = m['direction'] as String?
      ..category = m['category'] as String?
      ..section = m['section'] as String?
      ..done = (m['done'] ?? false) as bool
      ..dueDate = due == null ? null : DateTime.parse(due as String).toLocal()
      ..sortOrder = (m['sort_order'] as num?)?.toInt() ?? 0
      ..updatedAt = DateTime.parse(m['updated_at'] as String).toLocal()
      ..isSynced = true
      ..isDeleted = (m['is_deleted'] ?? false) as bool;
  }

  /// Build from a seed JSON object (local bootstrap data).
  static Item fromSeed(Map<String, dynamic> m, String uuid) {
    final due = m['dueDate'];
    return Item()
      ..uuid = uuid
      ..kind = m['kind'] as String
      ..title = (m['title'] ?? '') as String
      ..note = (m['note'] ?? '') as String
      ..amount = (m['amount'] as num?)?.toDouble()
      ..direction = m['direction'] as String?
      ..category = m['category'] as String?
      ..section = m['section'] as String?
      ..done = (m['done'] ?? false) as bool
      ..dueDate = due == null ? null : DateTime.parse(due as String)
      ..sortOrder = (m['sortOrder'] as num?)?.toInt() ?? 0
      ..updatedAt = DateTime.now().toUtc()
      ..isSynced = false
      ..isDeleted = false;
  }
}
