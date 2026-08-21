import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_event.dart';
import '../models/item.dart';
import '../services/app_lock_service.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/reset_service.dart';
import '../services/session_controller.dart';
import '../services/settings_service.dart';
import '../services/sync_service.dart';
import '../services/txn_category_service.dart';

export '../services/session_controller.dart' show AuthPhase, SessionState;

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

/// Google Sign-In + Supabase Auth wrapper. Inert unless Supabase is
/// configured — see [AuthService].
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Offline-tolerant auth state — drives [AuthGate].
///
/// Deliberately *not* a `StreamProvider` over `onAuthStateChange`: that stream
/// carries network failures as stream errors, which would collapse to
/// `AsyncError` and bounce a perfectly signed-in user to the sign-in screen
/// every time a token refresh couldn't reach the server. See
/// [SessionController].
final sessionProvider =
    StateNotifierProvider<SessionController, SessionState>(
        (ref) => SessionController.from(ref.watch(authServiceProvider)));

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

/// Every logged action (add/edit/complete/delete), newest first.
final historyProvider = StreamProvider<List<HistoryEvent>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.historyEvents
      .where()
      .sortByTimestampDesc()
      .watch(fireImmediately: true);
});

// Connectivity is read through `SyncService.isOnline` with a
// `ValueListenableBuilder` (as `lastSyncedAt` / `lastError` already are)
// rather than a provider: a plain `Provider<bool>` reading `online` once never
// rebuilt, so the cloud icon was frozen at whatever it showed on launch.

/// JSON export / import of the whole local DB — Settings → Data.
final backupServiceProvider =
    Provider<BackupService>((ref) => BackupService(ref.watch(isarProvider)));

/// Full wipe back to a fresh install — Settings → Data → Delete all data.
final resetServiceProvider = Provider<ResetService>((ref) => ResetService(
      ref.watch(isarProvider),
      ref.watch(sharedPreferencesProvider),
      ref.watch(syncServiceProvider),
    ));

/// Biometric / passcode gate — see [AppLockService] for why it exists.
final appLockServiceProvider = Provider<AppLockService>((ref) => AppLockService());

/// Whether the app lock is switched on, persisted across launches.
final appLockEnabledProvider =
    StateNotifierProvider<AppLockNotifier, bool>(
        (ref) => AppLockNotifier(ref.watch(sharedPreferencesProvider)));

/// Whether this device can authenticate at all (biometrics enrolled or a
/// passcode set) — gates the Settings toggle so the lock can't strand a user.
final appLockAvailableProvider = FutureProvider<bool>(
    (ref) => ref.watch(appLockServiceProvider).canLock());

/// System / Light / Dark, persisted across launches.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
    (ref) => ThemeModeNotifier(ref.watch(sharedPreferencesProvider)));

/// Monthly take-home used for the budget screen's Needs/Wants/Savings split.
final monthlySalaryProvider = StateNotifierProvider<SalaryNotifier, double>(
    (ref) => SalaryNotifier(ref.watch(sharedPreferencesProvider)));

/// The target Needs/Wants/Savings split itself — defaults to 65/15/20 but is
/// user-editable in Settings.
final budgetSplitProvider =
    StateNotifierProvider<BudgetSplitNotifier, BudgetSplit>(
        (ref) => BudgetSplitNotifier(ref.watch(sharedPreferencesProvider)));

/// The user's transaction categories (Settings → Transactions), persisted
/// across launches. Addable and removable; see [TxnCategoryNotifier].
final txnCategoriesProvider =
    StateNotifierProvider<TxnCategoryNotifier, List<String>>(
        (ref) => TxnCategoryNotifier(ref.watch(sharedPreferencesProvider)));

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
