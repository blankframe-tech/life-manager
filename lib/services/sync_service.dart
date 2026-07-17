import 'dart:async';

import 'package:isar_community/isar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/item.dart';

/// Offline-first sync engine over the single `items` table.
///
/// Every write lands in Isar instantly (the UI reacts to Isar streams, so it
/// never waits on the network) and is flagged `isSynced = false`. A background
/// worker pushes pending rows to Supabase; a realtime subscription pulls remote
/// changes back. Deletes are soft (tombstones) so they propagate across
/// devices. Conflict resolution is last-write-wins on `updatedAt`.
///
/// When Supabase isn't configured the engine is inert — the app is a fully
/// working local-only tracker.
class SyncService {
  SyncService(this.isar) {
    if (SupabaseConfig.isConfigured) {
      _online = true;
      _startRealtime();
      // Flush anything queued while offline.
      unawaited(pushPending());
    }
  }

  final Isar isar;
  bool _online = false;
  StreamSubscription? _sub;

  bool get online => _online;

  SupabaseClient get _db => Supabase.instance.client;

  /// Instant local write, then a background push.
  Future<void> save(Item item) async {
    item.updatedAt = DateTime.now().toUtc();
    item.isSynced = false;
    await isar.writeTxn(() => isar.items.put(item));
    unawaited(pushPending());
  }

  /// Soft-delete: keep the row as a tombstone so the deletion syncs out.
  Future<void> delete(Item item) async {
    item.isDeleted = true;
    item.updatedAt = DateTime.now().toUtc();
    item.isSynced = false;
    await isar.writeTxn(() => isar.items.put(item));
    unawaited(pushPending());
  }

  /// Push every not-yet-synced local row to the cloud.
  Future<void> pushPending() async {
    if (!_online) return;
    final pending =
        await isar.items.filter().isSyncedEqualTo(false).findAll();
    for (final item in pending) {
      try {
        await _db.from('items').upsert(item.toMap(), onConflict: 'uuid');
        item.isSynced = true;
        await isar.writeTxn(() => isar.items.put(item));
      } catch (_) {
        // Leave isSynced=false; a later push or reconnect retries.
      }
    }
  }

  void _startRealtime() {
    _sub = _db
        .from('items')
        .stream(primaryKey: ['uuid']).listen((rows) => _applyRemote(rows));
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

  void dispose() => _sub?.cancel();
}
