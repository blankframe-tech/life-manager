import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';

import '../models/item.dart';
import '../services/sync_service.dart';

/// The open Isar instance — overridden in `main()` after the DB opens.
final isarProvider = Provider<Isar>((ref) => throw UnimplementedError());

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
