import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';

/// The open Isar instance — overridden in `main()` after the DB opens.
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError());

/// The opened SharedPreferences instance — overridden in `main()`.
final sharedPreferencesProvider =
    Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// The offline-first sync engine.
final syncServiceProvider = Provider<SyncService>((ref) {
  final svc = SyncService(ref.watch(isarProvider));
  ref.onDispose(svc.dispose);
  return svc;
});

/// Reactive, sorted stream of the live (non-deleted) items for one section.
final itemsProvider =
    StreamProvider.family<List<Item>, String>((ref, kind) {
  final isar = ref.watch(isarProvider);
  return isar.items
      .filter()
      .kindEqualTo(kind)
      .isDeletedEqualTo(false)
      .sortBySortOrder()
      .thenByUpdatedAtDesc()
      .watch(fireImmediately: true);
});

/// Whether cloud sync is active (Supabase configured at build time).
final syncOnlineProvider = Provider<bool>((ref) {
  return ref.watch(syncServiceProvider).online;
});

/// System / Light / Dark, persisted across launches.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier(ref.watch(sharedPreferencesProvider)));

/// Monthly take-home used for the budget screen's 65/20/15 split.
final monthlySalaryProvider = StateNotifierProvider<SalaryNotifier, double>(
    (ref) => SalaryNotifier(ref.watch(sharedPreferencesProvider)));

/// Live search text per screen (keyed by [ItemKind]) — cleared when a screen
/// is left by resetting via the search bar's close button.
final searchQueryProvider =
    StateProvider.family<String, String>((ref, kind) => '');

/// Whether completed items are hidden, per checklist screen (task/buy).
final hideDoneProvider =
    StateProvider.family<bool, String>((ref, kind) => false);

/// Case-insensitive title/note filter used by every screen's search bar.
List<Item> filterBySearch(List<Item> items, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return items;
  return items
      .where((i) =>
          i.title.toLowerCase().contains(q) || i.note.toLowerCase().contains(q))
      .toList();
}
