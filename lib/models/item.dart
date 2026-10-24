// The `Item` class has two definitions with identical fields: the Isar
// collection on iOS / Android and a plain class on the web, where Isar's
// generated 64-bit schema ids don't compile and nothing may persist anyway.
// Field mapping is shared below, so a field missing from either one is a
// compile error on that platform.
import 'item_isar.dart' if (dart.library.js_interop) 'item_web.dart';

export 'item_isar.dart' if (dart.library.js_interop) 'item_web.dart';

/// The sections of the app. Stored as [Item.kind] (a String) so that the
/// value maps 1:1 onto the Supabase `items.kind` text column without depending
/// on enum ordinal stability.
class ItemKind {
  static const txn = 'txn'; // money actually spent / earned
  static const deal = 'deal'; // Dena Paona ledger
  static const budget = 'budget'; // 65/20/15 monthly plan
  static const task = 'task'; // to-dos
  static const buy = 'buy'; // shopping lists
  static const dream = 'dream'; // long-term wishes
  static const note = 'note'; // free-form notes (title + body)

  // Modules may add their own kinds (see lib/app_modules.dart); `kind` is
  // free text end to end, so a new kind needs no migration.
}

/// Direction of an [ItemKind.txn] entry — money out or money in. Shares the
/// `direction` column with [DealDirection]; the two never mix, because a row's
/// [Item.kind] decides which vocabulary applies.
class TxnDirection {
  static const spend = 'spend'; // money out (-)
  static const earn = 'earn'; // money in (+)
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

/// Serialise for Supabase / the backup JSON (snake_case columns). Shared by
/// both [Item] definitions.
Map<String, dynamic> itemToMap(Item i) => {
  'uuid': i.uuid,
  'kind': i.kind,
  'title': i.title,
  'note': i.note,
  'amount': i.amount,
  'direction': i.direction,
  'category': i.category,
  'section': i.section,
  'done': i.done,
  'due_date': i.dueDate?.toUtc().toIso8601String(),
  'sort_order': i.sortOrder,
  'updated_at': i.updatedAt.toUtc().toIso8601String(),
  'is_deleted': i.isDeleted,
};

/// Build from a Supabase row / backup JSON object.
Item itemFromMap(Map<String, dynamic> m) {
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
Item itemFromSeed(Map<String, dynamic> m, String uuid) {
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

/// A detached copy, including the local-only `id` and `isSynced`.
Item copyItem(Item i) => itemFromMap(itemToMap(i))
  ..id = i.id
  ..isSynced = i.isSynced;

/// Transaction-only view over the shared columns, so the log screen never
/// reads `dueDate` (which means "deadline" everywhere else) directly.
extension TxnFields on Item {
  /// When the money moved. Falls back to the row's last-write time for
  /// transactions written before a date was set — never null, because every
  /// transaction has to land in some week.
  DateTime get occurredAt => (dueDate ?? updatedAt).toLocal();

  set occurredAt(DateTime when) => dueDate = when;

  /// Money in is positive, money out negative. Un-directed rows count as
  /// spending, which is the direction a bare amount almost always means here.
  double get signedAmount =>
      direction == TxnDirection.earn ? (amount ?? 0) : -(amount ?? 0);

  bool get isEarning => direction == TxnDirection.earn;
}
