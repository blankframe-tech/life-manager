import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kTxnCategoriesKey = 'txn_categories';

/// What a fresh install starts with — a spread wide enough to log a normal
/// week without opening Settings first, and short enough that the picker
/// doesn't need scrolling. All of them are removable.
const kDefaultTxnCategories = <String>[
  'Food',
  'Transport',
  'Groceries',
  'Bills',
  'Health',
  'Shopping',
  'Salary',
  'Gifts',
];

/// The user's transaction categories, persisted across launches.
///
/// One flat list serves both spending and earning: which side a category falls
/// on is a property of the transaction, not of the name, and splitting the list
/// in two would mean picking a side for ambiguous ones like "Gifts".
///
/// Categories live in SharedPreferences rather than as [Item] rows — same as
/// salary and the budget split — so they're per-device and never sync. A
/// transaction stores its category as **text**, so one that arrives from
/// another device (or one you deleted here) still displays correctly; see
/// [mergeUsedCategories].
class TxnCategoryNotifier extends StateNotifier<List<String>> {
  TxnCategoryNotifier(this._prefs)
      : super(_prefs.getStringList(_kTxnCategoriesKey) ??
            List.of(kDefaultTxnCategories));

  final SharedPreferences _prefs;

  /// Adds [name], trimmed. Returns the stored form on success, or null if it
  /// was blank or already present (compared case-insensitively, so "food"
  /// can't shadow "Food").
  String? add(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    if (contains(clean)) return null;
    state = [...state, clean];
    _persist();
    return clean;
  }

  /// Removes [name]. Transactions already tagged with it keep the tag — the
  /// name just stops being offered for new ones.
  void remove(String name) {
    state = state.where((c) => c != name).toList();
    _persist();
  }

  bool contains(String name) =>
      state.any((c) => c.toLowerCase() == name.trim().toLowerCase());

  void _persist() => _prefs.setStringList(_kTxnCategoriesKey, state);
}

/// The categories to offer in a picker: the configured ones, plus any still
/// carried by an existing transaction.
///
/// Without this, a category deleted here (or created on another device, since
/// the list itself doesn't sync) would vanish from the picker while its
/// transactions kept showing it — and editing one of those would silently
/// reset its category. Order is preserved: configured first, strays after.
List<String> mergeUsedCategories(
    List<String> configured, Iterable<String?> used) {
  final seen = {for (final c in configured) c.toLowerCase()};
  final extra = <String>[];
  for (final name in used) {
    if (name == null || name.isEmpty) continue;
    if (seen.add(name.toLowerCase())) extra.add(name);
  }
  extra.sort();
  return [...configured, ...extra];
}
