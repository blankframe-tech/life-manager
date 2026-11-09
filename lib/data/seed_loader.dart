import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/item.dart';

/// One-time local bootstrap from `assets/seed/seed.json`.
///
/// The real seed file is git-ignored (it holds personal data). A committed
/// `seed.example.json` keeps the asset directory valid for fresh clones. If no
/// usable seed is present the app simply starts empty and fills from the cloud.
///
/// UUIDs are derived deterministically (v5) from kind+title so an accidental
/// re-seed can never create duplicates (the uuid index is unique+replace).
class SeedLoader {
  // Must be a valid RFC 4122 UUID — `uuid` 4.x validates the version nibble
  // before deriving a v5, and rejects anything that isn't a real UUID version.
  static final _rootNamespace = Namespace.url.value;
  static const _uuid = Uuid();

  /// Per-owner namespace for the deterministic seed UUIDs.
  ///
  /// `items.uuid` is a **global** primary key, so deriving it from
  /// `kind::title::index` under a fixed public namespace made every user who
  /// seeded the same data generate byte-identical UUIDs. That's not a read
  /// path — RLS still blocks cross-user access — but the second user's rows
  /// would collide with primary keys they can't see or update, so their pushes
  /// would fail forever with no way to resolve it. Folding the owner's id into
  /// the namespace keeps determinism *within* an account (the point of v5 here:
  /// an accidental re-seed can't duplicate) while making collisions across
  /// accounts impossible.
  ///
  /// Local-only installs have no user id and stay on the root namespace —
  /// there's no shared keyspace to collide in.
  static String _namespaceFor(String? userId) => userId == null
      ? _rootNamespace
      : _uuid.v5(_rootNamespace, 'life-manager::owner::$userId');

  /// Seeds the DB the first time only. Safe to call on every launch.
  static Future<void> seedIfNeeded(Isar isar) async {
    final marker = await _markerFile();
    if (await marker.exists()) return;

    // With cloud sync on, a second device must never seed: the uuids are
    // deterministic, so its pristine rows would upsert over the first device's
    // edits with a newer `updatedAt` and win last-write-wins. Only the device
    // that finds an empty cloud gets to seed.
    if (SupabaseConfig.isConfigured) {
      final empty = await _cloudIsEmpty();
      // Unreachable cloud: seed nothing and leave the marker unwritten so the
      // next launch can decide with a real answer.
      if (empty == null) return;
      if (!empty) {
        await marker.create(recursive: true);
        return;
      }
    }

    // `Supabase.instance` throws when it was never initialized, so only ask
    // for the owner id in configured (cloud) builds.
    final ownerId = SupabaseConfig.isConfigured
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    final items = await _readSeed(ownerId);
    if (items.isNotEmpty) {
      await isar.writeTxn(() => isar.items.putAll(items));
    }
    // Mark as seeded even when empty, so we don't re-scan the bundle forever.
    await marker.create(recursive: true);
  }

  static Future<List<Item>> _readSeed(String? ownerId) async {
    final raw = await _loadAsset();
    if (raw == null) return [];
    final namespace = _namespaceFor(ownerId);
    final decoded = jsonDecode(raw);
    final list = (decoded is Map ? decoded['items'] : decoded) as List?;
    if (list == null) return [];

    final items = <Item>[];
    for (var i = 0; i < list.length; i++) {
      final m = Map<String, dynamic>.from(list[i] as Map);
      final kind = (m['kind'] ?? ItemKind.task) as String;
      final title = (m['title'] ?? '') as String;
      final uuid = _uuid.v5(namespace, '$kind::$title::$i');
      final item = Item.fromSeed(m, uuid);
      if (item.sortOrder == 0) item.sortOrder = i;
      items.add(item);
    }
    return items;
  }

  /// Prefer the real (git-ignored) seed; fall back to the example if it holds
  /// real-shaped data. Returns null when nothing usable is bundled.
  static Future<String?> _loadAsset() async {
    for (final path in ['assets/seed/seed.json', 'assets/seed/seed.example.json']) {
      try {
        final s = await rootBundle.loadString(path);
        final decoded = jsonDecode(s);
        final list = (decoded is Map ? decoded['items'] : decoded) as List?;
        if (list != null && list.isNotEmpty) return s;
      } catch (_) {
        // Asset not bundled — try the next candidate.
      }
    }
    return null;
  }

  /// True when the cloud `items` table holds no rows, false when it holds some,
  /// null when it couldn't be reached (offline, bad keys, missing table).
  static Future<bool?> _cloudIsEmpty() async {
    try {
      final rows = await Supabase.instance.client
          .from('items')
          .select('uuid')
          .limit(1);
      return rows.isEmpty;
    } catch (_) {
      return null;
    }
  }

  static Future<File> _markerFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/.seeded_v1');
  }

  /// Records "seeding already happened" without seeding.
  ///
  /// Used by the full reset: a wipe must leave the app *empty*, and without the
  /// marker the next launch would helpfully re-import `seed.json` and undo it.
  static Future<void> markSeeded() async {
    final marker = await _markerFile();
    if (!await marker.exists()) await marker.create(recursive: true);
  }
}
