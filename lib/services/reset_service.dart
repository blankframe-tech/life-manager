import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/seed_loader.dart';
import '../models/history_event.dart';
import '../models/item.dart';
import 'sync_service.dart';

/// Wipes everything and returns the app to a fresh-install state.
///
/// Deletes items and activity history from **both** the local DB and the cloud,
/// then clears every stored preference. Signing out is left to the caller (the
/// cloud deletes need the session, so it has to happen last).
///
/// Ordering is chosen so a failure can't leave a half-wiped mess:
///
///  1. cloud history — the one delete that can be *refused* (see
///     `supabase/allow_history_delete.sql`), so it runs first and aborts the
///     whole reset while everything is still intact
///  2. cloud items
///  3. local DB
///  4. seed marker, so the next launch doesn't re-import `seed.json`
///  5. preferences
class ResetService {
  ResetService(this.isar, this.prefs, this.sync);

  final Isar isar;
  final SharedPreferences prefs;

  /// Needed only to cut the realtime subscriptions for the duration of the
  /// wipe — see [SyncService.suspendRealtime].
  final SyncService sync;

  SupabaseClient get _db => Supabase.instance.client;

  /// Whether a cloud wipe is possible right now.
  ///
  /// A local-only build (no keys) has no cloud to clear and resets freely. A
  /// cloud build with no session can't clear the server — and wiping only the
  /// device would be actively misleading, because the next sync pulls it all
  /// back. That case is refused rather than half-done.
  bool get canReset =>
      !SupabaseConfig.isConfigured || _db.auth.currentSession != null;

  Future<ResetReport> wipeEverything() async {
    final cloud = SupabaseConfig.isConfigured;
    if (cloud && _db.auth.currentSession == null) {
      throw const ResetBlockedException(
        'Not signed in, so your cloud copy can\'t be cleared — and it would '
        'sync straight back. Sign in and try again.',
      );
    }

    var cloudItems = 0;
    var cloudHistory = 0;

    // Must happen before the first delete: see [SyncService.suspendRealtime].
    sync.suspendRealtime();

    if (cloud) {
      final userId = _db.auth.currentUser!.id;
      // PostgREST refuses an unfiltered delete, and scoping by owner matches
      // what RLS enforces anyway. `.select()` makes it report what it removed.
      try {
        cloudHistory = (await _db
                .from('history_events')
                .delete()
                .eq('user_id', userId)
                .select('uuid'))
            .length;
      } on PostgrestException catch (e) {
        // Nothing has been deleted yet, so put sync back the way it was.
        sync.resumeRealtime();
        // 42501 = RLS refused it: the "owner delete" policy isn't there.
        if (e.code == '42501') {
          throw const ResetBlockedException(
            'The cloud activity log is still append-only, so it can\'t be '
            'deleted. Run supabase/allow_history_delete.sql in the Supabase '
            'dashboard first. Nothing has been deleted.',
          );
        }
        rethrow;
      }
      try {
        cloudItems = (await _db
                .from('items')
                .delete()
                .eq('user_id', userId)
                .select('uuid'))
            .length;
      } catch (_) {
        // The history log is already gone, so this is not recoverable — but
        // leaving realtime dead would silently stop sync for the rest of the
        // session, which is worse than letting it resubscribe.
        sync.resumeRealtime();
        rethrow;
      }
    }

    final localItems = await isar.items.count();
    final localHistory = await isar.historyEvents.count();
    await isar.writeTxn(() => isar.clear());

    // Without this the next launch treats an empty DB as a first run and
    // re-imports the bundled seed, quietly undoing the reset.
    await SeedLoader.markSeeded();

    // Salary, budget split, theme, app-lock switch, the monthly-reset marker —
    // all of it. Callers refresh their in-memory copies afterwards.
    await prefs.clear();

    return ResetReport(
      localItems: localItems,
      localHistory: localHistory,
      cloudItems: cloudItems,
      cloudHistory: cloudHistory,
      clearedCloud: cloud,
    );
  }
}

/// What a reset removed, for the confirmation message afterwards.
class ResetReport {
  const ResetReport({
    required this.localItems,
    required this.localHistory,
    required this.cloudItems,
    required this.cloudHistory,
    required this.clearedCloud,
  });

  final int localItems;
  final int localHistory;
  final int cloudItems;
  final int cloudHistory;

  /// False for a local-only build, where there was no cloud copy to begin with.
  final bool clearedCloud;

  String get summary {
    final where = clearedCloud ? ' from this device and the cloud' : '';
    return 'Deleted $localItems items and $localHistory history entries$where';
  }
}

/// The reset didn't run, and nothing was deleted. [message] is written for the
/// user and safe to show as-is.
class ResetBlockedException implements Exception {
  const ResetBlockedException(this.message);

  final String message;

  @override
  String toString() => message;
}
