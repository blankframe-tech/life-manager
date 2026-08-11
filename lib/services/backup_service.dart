import 'dart:convert';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/history_event.dart';
import '../models/item.dart';

/// Export / import of everything the app holds, as a single JSON file.
///
/// The on-disk shape reuses each model's `toMap()` — the same snake_case
/// serialization that goes to Supabase — so there's exactly one definition of
/// "what an item looks like outside Isar", and `fromMap()` parses it back.
///
/// Tombstones (`is_deleted`) and the full history log are both included: a
/// backup that dropped them would resurrect deleted items on import and lose
/// the activity trail.
class BackupService {
  BackupService(this.isar);

  final Isar isar;

  /// Bumped only if the shape changes incompatibly. [importJson] accepts this
  /// version and below.
  static const formatVersion = 1;
  static const formatName = 'life-manager-backup';

  /// Everything in the local DB as pretty-printed JSON.
  Future<String> buildJson() async {
    final items = await isar.items.where().findAll();
    final history = await isar.historyEvents.where().sortByTimestamp().findAll();
    return const JsonEncoder.withIndent('  ').convert({
      'format': formatName,
      'version': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'counts': {'items': items.length, 'history': history.length},
      'items': items.map((i) => i.toMap()).toList(),
      'history': history.map((h) => h.toMap()).toList(),
    });
  }

  /// Writes the export to a throwaway file and returns it, ready to hand to
  /// the share sheet.
  ///
  /// Deliberately the **temporary** directory, not Documents: the export is
  /// plaintext financial data, and Documents is exactly what
  /// `AppDelegate.excludeLocalDatabaseFromBackup` and Android's
  /// `data_extraction_rules.xml` work to keep out of platform backups. Temp
  /// isn't backed up and the OS reclaims it. Any previous export is deleted
  /// first so copies don't accumulate on disk.
  Future<File> writeExportFile() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    await _clearPreviousExports(dir);
    final file = File('${dir.path}/life-manager-backup-$stamp.json');
    return file.writeAsString(await buildJson(), flush: true);
  }

  Future<void> _clearPreviousExports(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (entity is File &&
            name.startsWith('life-manager-backup-') &&
            name.endsWith('.json')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Housekeeping only — never fail an export because cleanup didn't work.
    }
  }

  /// Checks that [raw] is a backup this build can read, and reports what's in
  /// it — so the confirmation dialog can state real numbers, and a wrong file
  /// is rejected before the user commits to anything.
  BackupSummary peek(String raw) {
    final decoded = _validate(raw);
    final exported = decoded['exportedAt'];
    return BackupSummary(
      items: (decoded['items'] as List).length,
      history: (decoded['history'] as List?)?.length ?? 0,
      exportedAt:
          exported is String ? DateTime.tryParse(exported)?.toLocal() : null,
    );
  }

  /// Shared gate for [peek] and [importJson]. Throws [BackupFormatException]
  /// with a user-safe message on anything unreadable.
  Map<String, dynamic> _validate(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const BackupFormatException("That file isn't valid JSON.");
    }
    if (decoded is! Map<String, dynamic> || decoded['format'] != formatName) {
      throw const BackupFormatException(
          "That doesn't look like a Life Manager backup.");
    }
    final version = (decoded['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw BackupFormatException(
          'That backup was written by a newer version of the app '
          '(format $version, this build reads $formatVersion).');
    }
    if (decoded['items'] is! List) {
      throw const BackupFormatException('The backup has no items list.');
    }
    return decoded;
  }

  /// Merges a backup into the local DB. Never destructive: nothing is removed,
  /// and an existing row is only overwritten by a **newer** one.
  ///
  /// The merge rules match [SyncService] deliberately, so importing behaves
  /// like receiving the same rows from the cloud:
  ///  - items: last-write-wins on `updated_at`
  ///  - history: insert-if-absent, since events are immutable once written
  ///
  /// Everything written is flagged `isSynced = false` so the sync engine pushes
  /// it to the cloud on the next attempt.
  Future<ImportReport> importJson(String raw) async {
    final decoded = _validate(raw);
    final rawItems = decoded['items'];
    final rawHistory = decoded['history'];

    var added = 0;
    var updated = 0;
    var skipped = 0;
    var historyAdded = 0;
    var malformed = 0;

    await isar.writeTxn(() async {
      for (final row in rawItems as List) {
        Item incoming;
        try {
          incoming = Item.fromMap(Map<String, dynamic>.from(row as Map));
        } catch (_) {
          // One bad row shouldn't abort a 500-row restore.
          malformed++;
          continue;
        }
        incoming.isSynced = false;
        final local =
            await isar.items.filter().uuidEqualTo(incoming.uuid).findFirst();
        if (local == null) {
          await isar.items.put(incoming);
          added++;
        } else if (local.updatedAt.isBefore(incoming.updatedAt)) {
          incoming.id = local.id;
          await isar.items.put(incoming);
          updated++;
        } else {
          skipped++;
        }
      }

      if (rawHistory is List) {
        for (final row in rawHistory) {
          HistoryEvent incoming;
          try {
            incoming =
                HistoryEvent.fromMap(Map<String, dynamic>.from(row as Map));
          } catch (_) {
            malformed++;
            continue;
          }
          incoming.isSynced = false;
          final exists = await isar.historyEvents
              .filter()
              .uuidEqualTo(incoming.uuid)
              .findFirst();
          if (exists == null) {
            await isar.historyEvents.put(incoming);
            historyAdded++;
          }
        }
      }
    });

    return ImportReport(
      itemsAdded: added,
      itemsUpdated: updated,
      itemsSkipped: skipped,
      historyAdded: historyAdded,
      malformed: malformed,
    );
  }
}

/// What a backup file contains, read without importing it.
class BackupSummary {
  const BackupSummary({
    required this.items,
    required this.history,
    this.exportedAt,
  });

  final int items;
  final int history;
  final DateTime? exportedAt;
}

/// What an import actually did — surfaced to the user so a restore that quietly
/// changed nothing is distinguishable from one that worked.
class ImportReport {
  const ImportReport({
    required this.itemsAdded,
    required this.itemsUpdated,
    required this.itemsSkipped,
    required this.historyAdded,
    required this.malformed,
  });

  final int itemsAdded;
  final int itemsUpdated;
  final int itemsSkipped;
  final int historyAdded;

  /// Rows that couldn't be parsed and were left out.
  final int malformed;

  bool get changedAnything =>
      itemsAdded > 0 || itemsUpdated > 0 || historyAdded > 0;

  String get summary {
    if (!changedAnything) {
      final tail = malformed > 0 ? ' ($malformed unreadable)' : '';
      return 'Nothing to import — everything was already up to date$tail';
    }
    final parts = <String>[
      if (itemsAdded > 0) '$itemsAdded added',
      if (itemsUpdated > 0) '$itemsUpdated updated',
      if (itemsSkipped > 0) '$itemsSkipped already current',
      if (historyAdded > 0) '$historyAdded history entries',
      if (malformed > 0) '$malformed unreadable',
    ];
    return 'Imported: ${parts.join(', ')}';
  }
}

/// The chosen file isn't a backup this build can read. Carries a message that's
/// safe to show the user as-is.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
