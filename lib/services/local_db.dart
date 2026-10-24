import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/history_event.dart';
import '../models/item.dart';

/// Opens the local Isar DB from **Application Support**, never Documents.
///
/// Documents is shown in the Files app (`UIFileSharingEnabled`), and Isar 3 has
/// no encryption, so the only file allowed there is the encrypted
/// `LifeManager.lmvault`. Builds before V2 kept the DB in Documents: the first
/// launch copies it across, opens the copy, then deletes the originals — so a
/// failure part-way leaves the old DB where it was.
Future<Isar> openLocalDb({Directory? documents, Directory? support}) async {
  final docs = documents ?? await getApplicationDocumentsDirectory();
  final sup = support ?? await getApplicationSupportDirectory();
  await sup.create(recursive: true);

  final oldDb = File('${docs.path}/default.isar');
  final newDb = File('${sup.path}/default.isar');
  final migrating = await oldDb.exists();
  if (migrating && !await newDb.exists()) await oldDb.copy(newDb.path);

  final isar = await Isar.open(
    [ItemSchema, HistoryEventSchema],
    directory: sup.path,
  );

  if (migrating) {
    // Isar's lock file is `-lck` on current builds, `.lock` on older notes.
    for (final suffix in ['', '-lck', '.lock']) {
      final f = File('${oldDb.path}$suffix');
      if (await f.exists()) await f.delete();
    }
  }
  return isar;
}
