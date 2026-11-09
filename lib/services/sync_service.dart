import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:http/http.dart' show ClientException;
import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/history_event.dart';
import '../models/item.dart';
import '../util/net.dart';

export '../util/net.dart' show isOfflineError;

/// Turns an exception into something safe to put on screen.
///
/// Raw `PostgrestException` / `AuthException` strings name tables, columns,
/// RLS policies and request details — useful in a debugger, not something to
/// render in Settings. Release builds get the summary alone; debug builds keep
/// the original appended so a failure is still diagnosable while developing.
String describeSyncError(Object error) {
  final summary = switch (error) {
    // Must precede the `AuthException` arm below, which it subclasses:
    // an unreachable server is not an expired session, and telling someone to
    // sign in again is both wrong and unactionable when they have no network.
    AuthRetryableFetchException() => 'No connection',
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
/// Two separate conditions gate the engine, and keeping them apart is what
/// makes the app usable on a plane:
///
///  * [enabled] — Supabase is configured **and** a session exists on this
///    device. Owner-only RLS rejects unauthenticated pushes, so without a
///    session there's nothing to attempt. An *expired* session still counts:
///    gotrue holds the refresh token and retries on its own.
///  * [reachable] — the last thing we tried actually got through. This flips
///    to false the moment a request fails for transport reasons and back to
///    true as soon as one succeeds.
///
/// [online] is both together, and is what the cloud indicator shows. While
/// enabled-but-unreachable the engine keeps queueing writes locally and probes
/// every 30s; on the first success it re-subscribes realtime (which re-emits a
/// full snapshot, catching up on anything missed) and flushes the backlog.
///
/// When Supabase isn't configured the engine is inert — the app is a fully
/// working local-only tracker.
class SyncService {
  SyncService(this.isar) {
    if (SupabaseConfig.isConfigured) {
      final session = _db.auth.currentSession;
      _enabled = session != null;
      // Only ever subscribe with a token that's currently valid. A channel
      // opened on an expired JWT fails as
      // `RealtimeSubscribeException(channelError, InvalidJWTToken)` and stays
      // dead — and at cold start the persisted access token is routinely
      // expired, with the refresh landing a moment later.
      if (session != null && !session.isExpired) _startRealtime();
      _authSub = _db.auth.onAuthStateChange.listen(
        (state) {
          final session = state.session;
          if (session == null) {
            if (state.event == AuthChangeEvent.signedOut) {
              _enabled = false;
              _stopRealtime();
              _publishOnline();
            }
            return;
          }
          final wasDisabled = !_enabled;
          final refreshed = state.event == AuthChangeEvent.tokenRefreshed;
          _enabled = true;
          // A token refresh only lands if the server answered, so it doubles
          // as our earliest and cheapest signal that the network is back.
          if (refreshed) _markReachable();
          // The channel binds its JWT at subscribe time and won't pick up a
          // later refresh on its own, so re-subscribe on every token change as
          // well as on the transition from disabled.
          if (!session.isExpired && (wasDisabled || refreshed)) {
            _stopRealtime();
            _startRealtime();
          }
          // Flush on every refresh, not just the reconnect edge: the token we
          // just got may be the first usable one since going offline, and
          // waiting for the 30s tick would leave the backlog sitting there.
          if (wasDisabled || refreshed) unawaited(pushPending());
          _publishOnline();
        },
        // Offline token refreshes arrive here rather than as events — see
        // [SessionController] for the full story. They must not disable the
        // engine; they just tell us the network is down.
        onError: (Object error, StackTrace _) {
          if (isOfflineError(error)) _markUnreachable();
        },
      );
      _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
      // The overwhelmingly common way a connection comes back is "user walks
      // into wifi, then opens the app". iOS also suspends our timer while
      // backgrounded, so without this the first tick after a resume can be a
      // full 30s away.
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(_tick()));
      _publishOnline();
    }
  }

  final Isar isar;

  /// A session exists — pushes are worth attempting. See the class doc.
  bool _enabled = false;

  /// The cloud answered us last time we asked. Starts optimistic: the first
  /// real request settles it either way.
  bool _reachable = true;

  StreamSubscription? _sub;
  StreamSubscription? _historySub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _retryTimer;
  AppLifecycleListener? _lifecycle;

  /// Whether sync is possible at all right now — drives the cloud icon.
  bool get online => _enabled && _reachable;

  /// Whether a session exists, regardless of connectivity. "Sync now" stays
  /// tappable on this rather than [online], so a user who knows their
  /// connection is back doesn't have to wait out the 30s probe.
  bool get enabled => _enabled;

  /// Whether the last thing we sent actually got through.
  bool get reachable => _reachable;

  /// Reactive mirror of [online] — plain provider reads can't see the
  /// transitions, which is why the indicator used to be stuck on whatever it
  /// showed at startup.
  final ValueNotifier<bool> isOnline = ValueNotifier(false);

  void _publishOnline() => isOnline.value = online;

  /// Returns true only on the false → true edge, so callers can act on
  /// "we just came back" without re-running on every subsequent success.
  bool _markReachable() {
    if (_reachable) return false;
    _reachable = true;
    _publishOnline();
    return true;
  }

  void _markUnreachable() {
    if (!_reachable) return;
    _reachable = false;
    _publishOnline();
  }

  /// The 30s heartbeat. With a backlog, pushing it *is* the probe; without one
  /// there's nothing to send, so ask the cheapest possible question instead —
  /// otherwise coming back online with a clean queue would go unnoticed until
  /// the next write or token refresh.
  Future<void> _tick() async {
    if (!_enabled) return;
    if (_reachable) {
      await pushPending();
      return;
    }
    if (await _probe()) {
      _stopRealtime();
      _startRealtime();
      await pushPending();
    }
  }

  /// One-row read used purely to test whether the cloud answers. Never touches
  /// [lastError]: its question is "is there a network", and answering it with
  /// an expired JWT would post "Session expired — sign in again" for what is
  /// actually a healthy reconnect.
  Future<bool> _probe() async {
    try {
      await _db.from('items').select('uuid').limit(1);
      return _markReachable();
    } catch (e) {
      // Anything that isn't a transport failure means the server answered —
      // it just didn't like the request. That's still proof of connectivity.
      return isOfflineError(e) ? false : _markReachable();
    }
  }

  /// Ensures the access token is usable before we spend requests on it.
  ///
  /// After a stretch offline the persisted token is routinely expired, and
  /// every push made with it is a guaranteed 401 that [describeSyncError]
  /// renders as "Session expired — sign in again" — the exact false alarm this
  /// whole path exists to avoid. gotrue de-duplicates concurrent refreshes of
  /// the same token, so racing its own 10s ticker here is safe.
  ///
  /// Returns false when the token can't be renewed, which offline means "try
  /// again later" and online means gotrue has already emitted `signedOut`.
  Future<bool> _ensureFreshToken() async {
    final session = _db.auth.currentSession;
    if (session == null) return false;
    if (!session.isExpired) return true;
    try {
      await _db.auth.refreshSession();
      _markReachable();
      return true;
    } catch (e) {
      if (isOfflineError(e)) _markUnreachable();
      return false;
    }
  }

  Future<int> _pendingCount() async =>
      await isar.items.filter().isSyncedEqualTo(false).count() +
      await isar.historyEvents.filter().isSyncedEqualTo(false).count();

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
  ///
  /// Probes first: the button is normally pressed moments after reconnecting,
  /// before the 30s tick has noticed, and [pushPending] alone wouldn't
  /// re-subscribe realtime so remote changes made while away would stay
  /// unseen.
  Future<({int pushed, int failed})> forceResync() async {
    if (!_reachable && await _probe()) {
      _stopRealtime();
      _startRealtime();
    }
    return pushPending();
  }

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
    // Gated on [_enabled], not [online]: attempting the push is how we find
    // out the network is back, so refusing to try while unreachable would
    // strand the queue.
    if (!_enabled) return (pushed: 0, failed: 0);
    if (!await _ensureFreshToken()) {
      final blocked = await _pendingCount();
      if (blocked > 0) lastError.value = 'No connection';
      return (pushed: 0, failed: blocked);
    }
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
        _markReachable();
        pushed++;
      } catch (e) {
        // Leave isSynced=false; a later push or reconnect retries.
        failed++;
        lastError.value = describeSyncError(e);
        // No point walking the rest of the queue with the network down — each
        // attempt burns its own retry budget. Count them as failed and stop;
        // the 30s tick picks the whole backlog up again once we reconnect.
        if (isOfflineError(e)) {
          _markUnreachable();
          return (pushed: pushed, failed: pending.length - pushed);
        }
      }
    }
    return (pushed: pushed, failed: failed);
  }

  Future<({int pushed, int failed})> _pushPendingHistory() async {
    // A failed item push already told us the network is down; skip rather than
    // repeat the discovery against a second table.
    if (!_reachable) return (pushed: 0, failed: 0);
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
        _markReachable();
        pushed++;
      } catch (e) {
        failed++;
        lastError.value = describeSyncError(e);
        if (isOfflineError(e)) {
          _markUnreachable();
          return (pushed: pushed, failed: pending.length - pushed);
        }
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
    if (online && session != null && !session.isExpired) {
      _stopRealtime();
      _startRealtime();
    }
  }

  void _startRealtime() {
    // Rows arriving at all proves the socket is up, so a reconnect that the
    // 30s probe hasn't noticed yet still clears the offline indicator.
    _sub = _db.from('items').stream(primaryKey: ['uuid']).listen(
      (rows) {
        _markReachable();
        _applyRemote(rows);
      },
      onError: (Object e, StackTrace _) {
        if (isOfflineError(e)) _markUnreachable();
      },
    );
    _historySub = _db.from('history_events').stream(primaryKey: ['uuid']).listen(
      (rows) {
        _markReachable();
        _applyRemoteHistory(rows);
      },
      onError: (Object e, StackTrace _) {
        if (isOfflineError(e)) _markUnreachable();
      },
    );
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
    _lifecycle?.dispose();
    lastSyncedAt.dispose();
    lastError.dispose();
    isOnline.dispose();
  }
}
