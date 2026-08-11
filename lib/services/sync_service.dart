import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/history_event.dart';
import '../models/item.dart';

/// Turns an exception into something safe to put on screen.
///
/// Raw `PostgrestException` / `AuthException` strings name tables, columns,
/// RLS policies and request details — useful in a debugger, not something to
/// render in Settings. Release builds get the summary alone; debug builds keep
/// the original appended so a failure is still diagnosable while developing.
String describeSyncError(Object error) {
  final summary = switch (error) {
    AuthException() => 'Session expired — sign in again',
    PostgrestException(:final code) => switch (code) {
        // RLS rejected the write — almost always a stale/absent session.
        '42501' => 'Not permitted — sign in again',
        'PGRST301' => 'Session expired — sign in again',
        '23505' => 'Conflicting record on the server',
        _ => 'Server rejected the change',
      },
    SocketException() => 'No connection',
    TimeoutException() => 'Connection timed out',
    ClientException() => 'No connection',
    _ => 'Sync failed',
  };
  return kDebugMode ? '$summary (debug: $error)' : summary;
}

/// Offline-first sync engine over the single `items` table.
///
/// Every write lands in Isar instantly (the UI reacts to Isar streams, so it
/// never waits on the network) and is flagged `isSynced = false`. A background
/// worker pushes pending rows to Supabase; a realtime subscription pulls remote
/// changes back. Deletes are soft (tombstones) so they propagate across
/// devices. Conflict resolution is last-write-wins on `updatedAt`.
///
/// "Online" means Supabase is configured **and** a signed-in session exists —
/// not just that build-time keys were provided, since owner-only RLS rejects
/// unauthenticated pushes anyway. A periodic timer retries pending pushes
/// while online, so a flaky connection recovers without the user having to
/// tap "Sync now".
///
/// When Supabase isn't configured the engine is inert — the app is a fully
/// working local-only tracker.
class SyncService {
  SyncService(this.isar) {
    if (SupabaseConfig.isConfigured) {
      final session = _db.auth.currentSession;
      _online = session != null;
      // Only ever subscribe with a token that's currently valid. A channel
      // opened on an expired JWT fails as
      // `RealtimeSubscribeException(channelError, InvalidJWTToken)` and stays
      // dead — and at cold start the persisted access token is routinely
      // expired, with the refresh landing a moment later.
      if (session != null && !session.isExpired) _startRealtime();
      _authSub = _db.auth.onAuthStateChange.listen((state) {
        final session = state.session;
        if (session == null) {
          if (_online) {
            _online = false;
            _stopRealtime();
          }
          return;
        }
        final wasOffline = !_online;
        _online = true;
        // The channel binds its JWT at subscribe time and won't pick up a
        // later refresh on its own, so re-subscribe on every token change as
        // well as on the transition from offline.
        if (!session.isExpired &&
            (wasOffline || state.event == AuthChangeEvent.tokenRefreshed)) {
          _stopRealtime();
          _startRealtime();
        }
        if (wasOffline) unawaited(pushPending());
      });
      _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_online) pushPending();
      });
    }
  }

  final Isar isar;
  bool _online = false;
  StreamSubscription? _sub;
  StreamSubscription? _historySub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _retryTimer;

  bool get online => _online;

  /// Last time a local push to Supabase succeeded — null if never synced.
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier(null);

  /// Message from the most recent push attempt's last failure — null if the
  /// most recent attempt had no failures (or none has run yet). Always a
  /// [describeSyncError] summary, never a raw exception: this string is shown
  /// in Settings, and raw Postgrest/Auth errors carry table names, policy
  /// names and request detail that don't belong on screen.
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Re-attempt pushing anything still pending — the Settings screen's
  /// manual "Sync now" action, for when a user comes back online.
  Future<({int pushed, int failed})> forceResync() => pushPending();

  SupabaseClient get _db => Supabase.instance.client;

  /// Instant local write, then a background push. Also logs a history event
  /// (created / edited / completed / uncompleted) — skipped for an undo of a
  /// delete, since the earlier `deleted` event already covers that moment.
  Future<void> save(Item item) async {
    final existing =
        await isar.items.filter().uuidEqualTo(item.uuid).findFirst();
    final isNew = existing == null;
    final doneChanged = existing != null && existing.done != item.done;
    final wasUndelete = existing != null && existing.isDeleted && !item.isDeleted;
    item.updatedAt = DateTime.now().toUtc();
    item.isSynced = false;
    await isar.writeTxn(() => isar.items.put(item));
    if (!wasUndelete) {
      await _logHistory(
        item,
        isNew
            ? HistoryAction.created
            : doneChanged
                ? (item.done
                    ? HistoryAction.completed
                    : HistoryAction.uncompleted)
                : HistoryAction.edited,
      );
    }
    unawaited(pushPending());
  }

  /// Soft-delete: keep the row as a tombstone so the deletion syncs out.
  Future<void> delete(Item item) async {
    item.isDeleted = true;
    item.updatedAt = DateTime.now().toUtc();
    item.isSynced = false;
    await isar.writeTxn(() => isar.items.put(item));
    await _logHistory(item, HistoryAction.deleted);
    unawaited(pushPending());
  }

  Future<void> _logHistory(Item item, String action) async {
    final event = HistoryEvent()
      ..uuid = const Uuid().v4()
      ..itemUuid = item.uuid
      ..itemKind = item.kind
      ..title = item.title
      ..action = action
      ..timestamp = DateTime.now().toUtc()
      ..isSynced = false;
    await isar.writeTxn(() => isar.historyEvents.put(event));
  }

  /// Push every not-yet-synced local row (items + history) to the cloud.
  /// Returns how many succeeded/failed so callers (e.g. the "Sync now"
  /// button) can report back to the user instead of failing silently.
  Future<({int pushed, int failed})> pushPending() async {
    lastError.value = null;
    if (!_online) return (pushed: 0, failed: 0);
    final items = await _pushPendingItems();
    final history = await _pushPendingHistory();
    return (
      pushed: items.pushed + history.pushed,
      failed: items.failed + history.failed,
    );
  }

  Future<({int pushed, int failed})> _pushPendingItems() async {
    final pending =
        await isar.items.filter().isSyncedEqualTo(false).findAll();
    var pushed = 0;
    var failed = 0;
    for (final item in pending) {
      try {
        await _db.from('items').upsert(item.toMap(), onConflict: 'uuid');
        item.isSynced = true;
        await isar.writeTxn(() => isar.items.put(item));
        lastSyncedAt.value = DateTime.now();
        pushed++;
      } catch (e) {
        // Leave isSynced=false; a later push or reconnect retries.
        failed++;
        lastError.value = describeSyncError(e);
      }
    }
    return (pushed: pushed, failed: failed);
  }

  Future<({int pushed, int failed})> _pushPendingHistory() async {
    final pending =
        await isar.historyEvents.filter().isSyncedEqualTo(false).findAll();
    var pushed = 0;
    var failed = 0;
    for (final event in pending) {
      try {
        await _db
            .from('history_events')
            .upsert(event.toMap(), onConflict: 'uuid');
        event.isSynced = true;
        await isar.writeTxn(() => isar.historyEvents.put(event));
        pushed++;
      } catch (e) {
        failed++;
        lastError.value = describeSyncError(e);
      }
    }
    return (pushed: pushed, failed: failed);
  }

  /// Detaches the realtime subscriptions without going offline.
  ///
  /// Used by the full reset. Deleting the cloud rows makes the `items` stream
  /// emit a snapshot per change, and a mid-deletion snapshot (still holding
  /// rows) that lands after the local DB was cleared would put them straight
  /// back. Cutting the subscriptions first removes the window entirely.
  void suspendRealtime() => _stopRealtime();

  /// Re-subscribes after a [suspendRealtime] that turned out to be unnecessary
  /// — e.g. a reset that aborted before deleting anything.
  void resumeRealtime() {
    final session = _db.auth.currentSession;
    if (_online && session != null && !session.isExpired) {
      _stopRealtime();
      _startRealtime();
    }
  }

  void _startRealtime() {
    _sub = _db
        .from('items')
        .stream(primaryKey: ['uuid']).listen((rows) => _applyRemote(rows));
    _historySub = _db.from('history_events').stream(primaryKey: ['uuid']).listen(
        (rows) => _applyRemoteHistory(rows));
  }

  void _stopRealtime() {
    _sub?.cancel();
    _sub = null;
    _historySub?.cancel();
    _historySub = null;
  }

  Future<void> _applyRemote(List<Map<String, dynamic>> rows) async {
    await isar.writeTxn(() async {
      for (final row in rows) {
        final remote = Item.fromMap(row);
        final local = await isar.items
            .filter()
            .uuidEqualTo(remote.uuid)
            .findFirst();
        // Last-write-wins: only accept the remote copy if it's newer.
        if (local == null || local.updatedAt.isBefore(remote.updatedAt)) {
          remote.id = local?.id ?? Isar.autoIncrement;
          await isar.items.put(remote);
        }
      }
    });
  }

  /// History rows are immutable once created, so unlike [_applyRemote] there's
  /// no last-write-wins merge — just insert whatever isn't already local.
  Future<void> _applyRemoteHistory(List<Map<String, dynamic>> rows) async {
    await isar.writeTxn(() async {
      for (final row in rows) {
        final remote = HistoryEvent.fromMap(row);
        final local = await isar.historyEvents
            .filter()
            .uuidEqualTo(remote.uuid)
            .findFirst();
        if (local == null) {
          await isar.historyEvents.put(remote);
        }
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _historySub?.cancel();
    _authSub?.cancel();
    _retryTimer?.cancel();
    lastSyncedAt.dispose();
    lastError.dispose();
  }
}
