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
// backups and the encrypted vault), and SharedPreferences is plaintext.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/item.dart';
import '../services/sync_service.dart';
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

class CanvasNotifier extends StateNotifier<CanvasState> {
  CanvasNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static CanvasState _load(SharedPreferences prefs) {
    final raw = prefs.getString(kCanvasPrefsKey);
    if (raw == null) return const CanvasState();
    try {
      return CanvasState.fromJson(jsonDecode(raw));
    } on FormatException {
      return const CanvasState();
    }
  }

  void _save(CanvasState next) {
    state = next;
    _prefs.setString(kCanvasPrefsKey, jsonEncode(next.toJson()));
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
    _prefs.remove(kCanvasPrefsKey);
  }
}

/// Saves the rows in [items] that the database doesn't have yet, and returns
/// how many. A row from an earlier import of the same text is left as the
/// user last left it: edited, ticked or deleted.
Future<int> writeNewItems(Isar isar, SyncService sync, List<Item> items) async {
  var written = 0;
  for (final item in items) {
    final exists = await isar.items.filter().uuidEqualTo(item.uuid).count() > 0;
    if (exists) continue;
    await sync.save(item);
    written++;
  }
  return written;
}
