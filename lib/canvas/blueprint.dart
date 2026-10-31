// The canvas blueprint: the app's shape, as data.
//
// A blueprint is compiled once (when the user brings in their notes) and
// saved. At launch the app decodes it and draws it; it never re-reads the
// notes or re-infers the layout. See docs/CANVAS.md.
//
// Pure Dart on purpose: the same JSON is what a language model with
// structured output would emit later, so [Blueprint.fromJson] treats its
// input as untrusted.

/// How a section draws its items.
enum SectionType {
  /// Tick-off list (to-dos, bazaar list). Shows a total when items have prices.
  checklist,

  /// Lines with amounts (a budget, an expense log). Shows a running total.
  ledger,

  /// Who owes whom. Shows a net balance.
  people,

  /// Free text, kept as written.
  notes,

  /// Someday things.
  goals,
}

/// The coarse area a section belongs to. Tabs are made from domains.
enum Domain { money, people, todo, shopping, goals, notes }

/// Tab title for a domain.
const kDomainTitles = {
  Domain.money: 'Money',
  Domain.people: 'People',
  Domain.todo: 'To-do',
  Domain.shopping: 'Shopping',
  Domain.goals: 'Dreams',
  Domain.notes: 'Notes',
};

/// A small domain joins its family's tab instead of getting its own.
const _family = {
  Domain.people: Domain.money,
  Domain.shopping: Domain.todo,
  Domain.goals: Domain.notes,
};

/// Up to this many sections fit on one page: no bottom nav at all, like one
/// long pinned note.
const kSinglePageMax = 5;
const kMaxTabs = 6;
const _maxSectionsPerTab = 40;
const _maxTitle = 80;

/// One block on the canvas: a titled, filtered view over `Item`s with
/// `kind == [kind]` and `section == [id]`.
class SectionSpec {
  const SectionSpec({
    required this.id,
    required this.title,
    required this.type,
    required this.kind,
    required this.domain,
    required this.order,
  });

  /// Stable id, also stored in `Item.section`.
  final String id;
  final String title;
  final SectionType type;

  /// The `Item.kind` its rows use (`task`, `buy`, `budget`, `txn`, `deal`,
  /// `note`, `dream`), so the classic module screens show the same rows.
  final String kind;
  final Domain domain;

  /// Position in the user's own material. Sections keep this order, because
  /// people remember where things are in their note.
  final int order;

  SectionSpec copyWith({String? title, Domain? domain}) => SectionSpec(
    id: id,
    title: title ?? this.title,
    type: type,
    kind: kind,
    domain: domain ?? this.domain,
    order: order,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'type': type.name,
    'kind': kind,
    'domain': domain.name,
    'order': order,
  };

  /// Null when [j] is not a usable section.
  static SectionSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'], kind = j['kind'];
    final type = _byName(SectionType.values, j['type']);
    final domain = _byName(Domain.values, j['domain']);
    if (id is! String || id.isEmpty || id.length > 64) return null;
    if (title is! String || kind is! String || kind.isEmpty) return null;
    if (kind.length > 32 || type == null || domain == null) return null;
    final order = j['order'];
    return SectionSpec(
      id: id,
      title: _clip(title.trim().isEmpty ? 'Untitled' : title.trim()),
      type: type,
      kind: kind,
      domain: domain,
      order: order is int ? order : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SectionSpec &&
      other.id == id &&
      other.title == title &&
      other.type == type &&
      other.kind == kind &&
      other.domain == domain &&
      other.order == order;

  @override
  int get hashCode => Object.hash(id, title, type, kind, domain, order);
}

/// One bottom-nav destination.
class CanvasTab {
  const CanvasTab({
    required this.id,
    required this.title,
    required this.domain,
    required this.sections,
  });
  final String id;
  final String title;

  /// Picks the icon and colour.
  final Domain domain;
  final List<SectionSpec> sections;

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'domain': domain.name,
    'sections': [for (final s in sections) s.toJson()],
  };
}

/// The whole shape. Zero or one tab draws a single page with no bottom nav;
/// two to six draw a bottom nav.
class Blueprint {
  const Blueprint(this.tabs);

  static const format = 'life-manager-canvas';
  static const version = 1;

  final List<CanvasTab> tabs;

  bool get hasNav => tabs.length >= 2;

  Iterable<SectionSpec> get sections => tabs.expand((t) => t.sections);

  Map<String, Object> toJson() => {
    'format': format,
    'version': version,
    'tabs': [for (final t in tabs) t.toJson()],
  };

  /// Validates as it reads: wrong format or a newer version gives null,
  /// unusable sections and empty tabs are dropped, and the tab count is capped.
  static Blueprint? fromJson(Object? j) {
    if (j is! Map || j['format'] != format) return null;
    final v = j['version'];
    if (v is! int || v > version) return null;
    final rawTabs = j['tabs'];
    if (rawTabs is! List) return null;
    final tabs = <CanvasTab>[];
    final seen = <String>{};
    for (final t in rawTabs) {
      if (t is! Map || tabs.length == kMaxTabs) continue;
      final rawSections = t['sections'];
      final sections = <SectionSpec>[
        if (rawSections is List)
          for (final s in rawSections.take(_maxSectionsPerTab))
            if (SectionSpec.fromJson(s) case final spec?)
              if (seen.add(spec.id)) spec,
      ];
      if (sections.isEmpty) continue;
      final domain =
          _byName(Domain.values, t['domain']) ?? sections.first.domain;
      final title = t['title'];
      final id = t['id'];
      tabs.add(
        CanvasTab(
          id: id is String && id.isNotEmpty ? _clip(id) : domain.name,
          title: title is String && title.trim().isNotEmpty
              ? _clip(title.trim())
              : kDomainTitles[domain]!,
          domain: domain,
          sections: sections,
        ),
      );
    }
    return Blueprint(tabs);
  }
}

/// What the user changed by hand. Kept apart from the compiled sections so
/// it survives every re-shape.
class SectionOverride {
  const SectionOverride({this.title, this.hidden = false, this.domain});
  final String? title;
  final bool hidden;

  /// Moved to another tab on purpose.
  final Domain? domain;

  Map<String, Object> toJson() => {
    'title': ?title,
    if (hidden) 'hidden': true,
    'domain': ?domain?.name,
  };

  static SectionOverride fromJson(Object? j) {
    if (j is! Map) return const SectionOverride();
    final title = j['title'];
    return SectionOverride(
      title: title is String && title.trim().isNotEmpty
          ? _clip(title.trim())
          : null,
      hidden: j['hidden'] == true,
      domain: _byName(Domain.values, j['domain']),
    );
  }
}

/// Arranges [sections] into tabs. Deterministic: the same input always gives
/// the same blueprint.
///
/// - Hidden sections are left out; renamed and moved ones use the override.
/// - Up to [kSinglePageMax] sections, or a single domain: one page, no nav.
/// - Otherwise one tab per domain, in the order the domains first appear in
///   the user's material. A domain with one section joins its family
///   (People → Money, Shopping → To-do, Dreams → Notes) unless the user moved
///   it there by hand.
Blueprint layout(
  List<SectionSpec> sections, [
  Map<String, SectionOverride> overrides = const {},
]) {
  final visible = <SectionSpec>[];
  for (final s in sections) {
    final o = overrides[s.id];
    if (o == null) {
      visible.add(s);
    } else if (!o.hidden) {
      visible.add(s.copyWith(title: o.title, domain: o.domain));
    }
  }
  visible.sort((a, b) => a.order.compareTo(b.order));
  if (visible.isEmpty) return const Blueprint([]);

  final groups = <Domain, List<SectionSpec>>{};
  for (final s in visible) {
    groups.putIfAbsent(s.domain, () => []).add(s);
  }
  if (visible.length <= kSinglePageMax || groups.length == 1) {
    return Blueprint([
      CanvasTab(
        id: 'home',
        title: groups.length == 1 ? kDomainTitles[groups.keys.first]! : 'Home',
        domain: visible.first.domain,
        sections: visible,
      ),
    ]);
  }

  bool pinned(Domain d) => groups[d]!.any((s) => overrides[s.id]?.domain == d);
  for (final d in Domain.values) {
    final parent = _family[d];
    if (parent == null || !groups.containsKey(d)) continue;
    if (groups[d]!.length >= 2 || pinned(d) || !groups.containsKey(parent)) {
      continue;
    }
    groups[parent]!
      ..addAll(groups.remove(d)!)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  final tabs = [
    for (final e in groups.entries)
      CanvasTab(
        id: e.key.name,
        title: kDomainTitles[e.key]!,
        domain: e.key,
        sections: e.value,
      ),
  ];
  // Six domains means six tabs at most, but keep the cap explicit.
  return Blueprint(tabs.take(kMaxTabs).toList());
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

String _clip(String s) => s.length <= _maxTitle ? s : s.substring(0, _maxTitle);
