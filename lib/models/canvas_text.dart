import 'package:isar_community/isar.dart';

part 'canvas_text.g.dart';

/// The canvas's own words: source file names, section headings and renames,
/// as one JSON row. They live here, in the DB that iOS backups skip, and not
/// with the rest of the canvas in SharedPreferences, which is plaintext
/// NSUserDefaults and is backed up. See `lib/canvas/canvas_store.dart`.
@collection
class CanvasText {
  /// Always 0: there is one row.
  Id id = 0;

  late String json;
}
