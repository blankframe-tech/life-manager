// Where the canvas lives between launches, and the memory-for-compute trade
// that keeps it instant:
//
//  - Parsing and classifying (the expensive part) runs once per source, when
//    it is added. Its result, the source's sections, is saved under the
//    source's content hash. Adding a second note never re-reads the first,
//    and adding the same note twice is recognised and skipped.
//  - The arranged blueprint is saved too. A launch decodes it and draws;
//    nothing is inferred at startup.
//  - A hand edit (rename, hide, move) re-runs only the layout over the saved
//    sections. Cheap, and the edit survives every later re-shape.
//
// The raw text is not kept: its rows are already in the database (and so in
// the encrypted vault). SharedPreferences is plaintext and iOS backs it up,
// so it gets only the shape (ids, kinds, order, domains). The user's own
// words in it (file names, headings, renames) go to [CanvasTextStore], which
// the app backs with the Isar DB.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';
import '../services/sync_service.dart';
import '../store/local_store.dart';
import 'blueprint.dart';
import 'shaper.dart';

const kCanvasPrefsKey = 'canvas_state_v1';

class CanvasState {
  const CanvasState({
    this.sources = const [],
    this.overrides = const {},
    this.blueprint,
  });

  /// Every source compiled so far, oldest first. Sections only, no rows.
  final List<CompiledSource> sources;
  final Map<String, SectionOverride> overrides;

  /// The saved arrangement. Null means the classic module layout.
  final Blueprint? blueprint;

  bool get active => blueprint != null;

  List<SectionSpec> get allSections => [for (final s in sources) ...s.sections];

  List<SectionSpec> get hiddenSections => [
    for (final s in allSections)
      if (overrides[s.id]?.hidden ?? false) s,
  ];

  Map<String, Object> toJson() => {
    'shaper': Shaper.version,
    'sources': [for (final s in sources) s.toJson()],
    'overrides': {for (final e in overrides.entries) e.key: e.value.toJson()},
    'blueprint': ?blueprint?.toJson(),
  };

  static CanvasState fromJson(Object? j) {
    if (j is! Map) return const CanvasState();
    final rawSources = j['sources'];
    final rawOverrides = j['overrides'];
    final sources = <CompiledSource>[
      if (rawSources is List)
        for (final s in rawSources) ?CompiledSource.fromJson(s),
    ];
    final overrides = <String, SectionOverride>{
      if (rawOverrides is Map)
        for (final e in rawOverrides.entries)
          if (e.key is String)
            e.key as String: SectionOverride.fromJson(e.value),
    };
    var blueprint = Blueprint.fromJson(j['blueprint']);
    // A saved blueprint that no longer reads is rebuilt from the sections.
    if (blueprint == null && j['blueprint'] != null && sources.isNotEmpty) {
      blueprint = layout([for (final s in sources) ...s.sections], overrides);
    }
    return CanvasState(
      sources: sources,
      overrides: overrides,
      blueprint: blueprint,
    );
  }
}

/// What adding some sources would do, before anything is saved.
class CanvasPreview {
  const CanvasPreview({
    required this.fresh,
    required this.alreadyIn,
    required this.blueprint,
  });

  /// Sources not in the canvas yet, compiled.
  final List<CompiledSource> fresh;

  /// How many of the given sources were already in the canvas.
  final int alreadyIn;

  /// The arrangement after adding [fresh].
  final Blueprint blueprint;

  List<Item> get items => [for (final s in fresh) ...s.items];
  bool get hasNewSections => fresh.any((s) => s.sections.isNotEmpty);

  int countIn(String sectionId) =>
      items.where((i) => i.section == sectionId).length;
}

/// Holds the canvas's own words as JSON. In memory here (tests and the web
/// build); iOS / Android use `IsarCanvasText` (`canvas_text_isar.dart`).
class CanvasTextStore {
  String? _json;
  String? read() => _json;

  /// Null forgets them.
  Future<void> write(String? json) async => _json = json;
}

/// Moves the user's words out of a [CanvasState.toJson] map, in place:
/// source names, section titles (as compiled and as shown) and renames.
Map<String, Map<String, String>> _takeText(Map j) {
  final names = <String, String>{}, titles = <String, String>{};
  final renames = <String, String>{}, shown = <String, String>{};
  void blank(Object? s, Map<String, String> into) {
    if (s is Map && s['id'] is String && s['title'] is String) {
      into[s['id'] as String] = s['title'] as String;
      s['title'] = '';
    }
  }

  for (final src in _list(j['sources'])) {
    if (src is! Map) continue;
    if (src['hash'] is String && src['name'] is String) {
      names[src['hash'] as String] = src['name'] as String;
      src['name'] = '';
    }
    for (final s in _list(src['sections'])) {
      blank(s, titles);
    }
  }
  final overrides = j['overrides'];
  if (overrides is Map) {
    for (final e in overrides.entries) {
      final o = e.value;
      if (o is Map && o['title'] is String && e.key is String) {
        renames[e.key as String] = o.remove('title') as String;
      }
    }
  }
  final bp = j['blueprint'];
  if (bp is Map) {
    for (final t in _list(bp['tabs'])) {
      if (t is Map) _list(t['sections']).forEach((s) => blank(s, shown));
    }
  }
  return {'names': names, 'titles': titles, 'renames': renames, 'shown': shown};
}

/// The inverse of [_takeText]. A word that is missing stays blank, which
/// [SectionSpec.fromJson] shows as "Untitled".
void _putText(Map j, Map text) {
  Map words(String k) => text[k] is Map ? text[k] as Map : const {};
  final names = words('names'), titles = words('titles');
  final renames = words('renames'), shown = words('shown');
  void fill(Object? s, Map from) {
    if (s is Map && from[s['id']] is String) s['title'] = from[s['id']];
  }

  for (final src in _list(j['sources'])) {
    if (src is! Map) continue;
    if (names[src['hash']] is String) src['name'] = names[src['hash']];
    _list(src['sections']).forEach((s) => fill(s, titles));
  }
  final overrides = j['overrides'];
  if (overrides is Map) {
    for (final e in overrides.entries) {
      if (e.value is Map && renames[e.key] is String) {
        (e.value as Map)['title'] = renames[e.key];
      }
    }
  }
  final bp = j['blueprint'];
  if (bp is Map) {
    for (final t in _list(bp['tabs'])) {
      if (t is Map) _list(t['sections']).forEach((s) => fill(s, shown));
    }
  }
}

List<Object?> _list(Object? v) => v is List ? v : const [];

class CanvasNotifier extends StateNotifier<CanvasState> {
  CanvasNotifier(this._prefs, [CanvasTextStore? text])
    : _text = text ?? CanvasTextStore(),
      super(const CanvasState()) {
    _load();
  }

  final SharedPreferences _prefs;
  final CanvasTextStore _text;

  void _load() {
    final raw = _prefs.getString(kCanvasPrefsKey);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      // An older build saved the words in prefs too.
      final legacy = _takeText(j);
      final hasLegacy = legacy.values.any(
        (m) => m.values.any((w) => w.isNotEmpty),
      );
      final stored = hasLegacy ? legacy : jsonDecode(_text.read() ?? '{}');
      _putText(j, stored is Map ? stored : const {});
      final loaded = CanvasState.fromJson(j);
      if (hasLegacy) {
        _save(loaded);
      } else {
        state = loaded;
      }
    } catch (e) {
      // A corrupt state or an unreadable DB: the classic layout, nothing lost.
      debugPrint('canvas: not loaded: $e');
    }
  }

  void _save(CanvasState next) {
    state = next;
    final j = next.toJson();
    final text = jsonEncode(_takeText(j));
    unawaited(_persist(text, jsonEncode(j)));
  }

  /// Prefs change only after the words are stored, so a failed write keeps
  /// the last saved state (an older build's still holds its words).
  Future<void> _persist(String? text, String? shape) async {
    try {
      await _text.write(text);
      shape == null
          ? await _prefs.remove(kCanvasPrefsKey)
          : await _prefs.setString(kCanvasPrefsKey, shape);
    } catch (e) {
      debugPrint('canvas: not saved: $e');
    }
  }

  /// Compiles the [docs] that are new to the canvas. Saves nothing.
  CanvasPreview preview(List<SourceDoc> docs, {DateTime? now}) {
    final known = {for (final s in state.sources) s.hash};
    final fresh = <CompiledSource>[];
    var alreadyIn = 0;
    for (final d in docs) {
      if (!known.add(Shaper.hashOf(d.text))) {
        alreadyIn++;
        continue;
      }
      fresh.add(
        Shaper.compile(
          d,
          orderBase: (state.sources.length + fresh.length) * kOrderStride,
          now: now,
        ),
      );
    }
    return CanvasPreview(
      fresh: fresh,
      alreadyIn: alreadyIn,
      blueprint: layout([
        ...state.allSections,
        for (final s in fresh) ...s.sections,
      ], state.overrides),
    );
  }

  /// Saves [p]'s sources and arrangement and switches the app to the canvas.
  /// Write the rows first ([writeNewItems]) so the canvas opens full.
  void commit(CanvasPreview p) {
    if (!p.hasNewSections && !state.active) return;
    _save(
      CanvasState(
        sources: [...state.sources, ...p.fresh],
        overrides: state.overrides,
        blueprint: p.blueprint,
      ),
    );
  }

  void rename(String sectionId, String title) {
    final t = title.trim();
    _override(
      sectionId,
      (o) => SectionOverride(
        title: t.isEmpty ? null : t,
        hidden: o.hidden,
        domain: o.domain,
      ),
    );
  }

  void hide(String sectionId) => _override(
    sectionId,
    (o) => SectionOverride(title: o.title, hidden: true, domain: o.domain),
  );

  void moveTo(String sectionId, Domain domain) => _override(
    sectionId,
    (o) => SectionOverride(title: o.title, hidden: o.hidden, domain: domain),
  );

  void unhideAll() {
    final next = {
      for (final e in state.overrides.entries)
        e.key: SectionOverride(title: e.value.title, domain: e.value.domain),
    };
    _relayout(next);
  }

  void _override(String id, SectionOverride Function(SectionOverride) change) =>
      _relayout({
        ...state.overrides,
        id: change(state.overrides[id] ?? const SectionOverride()),
      });

  void _relayout(Map<String, SectionOverride> overrides) {
    if (!state.active) return;
    _save(
      CanvasState(
        sources: state.sources,
        overrides: overrides,
        blueprint: layout(state.allSections, overrides),
      ),
    );
  }

  /// Back to the classic layout. Rows stay; only the shape is forgotten.
  void reset() {
    state = const CanvasState();
    unawaited(_persist(null, null));
  }
}

/// Saves the rows in [items] that the database doesn't have yet, and returns
/// how many. A row from an earlier import of the same text is left as the
/// user last left it: edited, ticked or deleted.
Future<int> writeNewItems(
  LocalStore store,
  SyncService sync,
  List<Item> items,
) async {
  var written = 0;
  for (final item in items) {
    if (await store.item(item.uuid) != null) continue;
    await sync.save(item);
    written++;
  }
  return written;
}
