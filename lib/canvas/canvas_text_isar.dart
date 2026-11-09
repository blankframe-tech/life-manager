import 'package:isar_community/isar.dart';

import '../models/canvas_text.dart';
import 'canvas_store.dart';

// iOS / Android only: Isar's generated schema ids don't compile to JavaScript,
// so the web build never imports this file (it keeps [CanvasTextStore]).

/// [CanvasTextStore] in the Isar DB, which is excluded from iOS backups.
class IsarCanvasText extends CanvasTextStore {
  IsarCanvasText(this.isar);
  final Isar isar;

  @override
  String? read() => isar.canvasTexts.getSync(0)?.json;

  // Async, not writeTxnSync: a sync write throws while any other async write
  // is running. Isar runs async writes in the order they were queued.
  @override
  Future<void> write(String? json) => isar.writeTxn(() async {
    json == null
        ? await isar.canvasTexts.delete(0)
        : await isar.canvasTexts.put(CanvasText()..json = json);
  });
}
