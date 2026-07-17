import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
  static const _namespace = '6f9619ff-8b86-d011-b42d-00c04fc964ff';
  static const _uuid = Uuid();

  /// Seeds the DB the first time only. Safe to call on every launch.
  static Future<void> seedIfNeeded(Isar isar) async {
    final marker = await _markerFile();
    if (await marker.exists()) return;

    final items = await _readSeed();
    if (items.isNotEmpty) {
      await isar.writeTxn(() => isar.items.putAll(items));
    }
    // Mark as seeded even when empty, so we don't re-scan the bundle forever.
    await marker.create(recursive: true);
  }

  static Future<List<Item>> _readSeed() async {
    final raw = await _loadAsset();
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    final list = (decoded is Map ? decoded['items'] : decoded) as List?;
    if (list == null) return [];

    final items = <Item>[];
    for (var i = 0; i < list.length; i++) {
      final m = Map<String, dynamic>.from(list[i] as Map);
      final kind = (m['kind'] ?? ItemKind.task) as String;
      final title = (m['title'] ?? '') as String;
      final uuid = _uuid.v5(_namespace, '$kind::$title::$i');
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

  static Future<File> _markerFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/.seeded_v1');
  }
}
