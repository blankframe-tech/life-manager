import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/canvas/blueprint.dart';

SectionSpec spec(String id, Domain d, int order, {SectionType? type}) =>
    SectionSpec(
      id: id,
      title: id,
      type: type ?? SectionType.checklist,
      kind: 'task',
      domain: d,
      order: order,
    );

void main() {
  group('layout', () {
    test('no sections: no tabs', () {
      expect(layout([]).tabs, isEmpty);
    });

    test('a few sections stay on one page with no nav, in source order', () {
      final bp = layout([
        spec('c', Domain.notes, 3),
        spec('a', Domain.money, 1),
        spec('b', Domain.todo, 2),
      ]);
      expect(bp.tabs, hasLength(1));
      expect(bp.hasNav, isFalse);
      expect(bp.tabs.single.sections.map((s) => s.id), ['a', 'b', 'c']);
    });

    test('many sections of one domain still make one page', () {
      final bp = layout([
        for (var i = 0; i < 9; i++) spec('t$i', Domain.todo, i),
      ]);
      expect(bp.tabs, hasLength(1));
      expect(bp.tabs.single.title, 'To-do');
    });

    test('many sections split into tabs by domain, in first-seen order', () {
      final bp = layout([
        spec('n1', Domain.notes, 0),
        spec('m1', Domain.money, 1),
        spec('t1', Domain.todo, 2),
        spec('m2', Domain.money, 3),
        spec('t2', Domain.todo, 4),
        spec('n2', Domain.notes, 5),
      ]);
      expect(bp.hasNav, isTrue);
      expect(bp.tabs.map((t) => t.title), ['Notes', 'Money', 'To-do']);
      expect(bp.tabs[1].sections.map((s) => s.id), ['m1', 'm2']);
    });

    test('a lone small domain joins its family tab', () {
      final bp = layout([
        spec('m1', Domain.money, 0),
        spec('p1', Domain.people, 1),
        spec('m2', Domain.money, 2),
        spec('t1', Domain.todo, 3),
        spec('s1', Domain.shopping, 4),
        spec('t2', Domain.todo, 5),
      ]);
      expect(bp.tabs.map((t) => t.title), ['Money', 'To-do']);
      expect(bp.tabs.first.sections.map((s) => s.id), ['m1', 'p1', 'm2']);
    });

    test('a lone domain with no family on the canvas keeps its own tab', () {
      final bp = layout([
        spec('p1', Domain.people, 0),
        spec('t1', Domain.todo, 1),
        spec('t2', Domain.todo, 2),
        spec('n1', Domain.notes, 3),
        spec('n2', Domain.notes, 4),
        spec('n3', Domain.notes, 5),
      ]);
      expect(bp.tabs.map((t) => t.title), ['People', 'To-do', 'Notes']);
    });

    test('six full domains give six tabs, never more', () {
      final bp = layout([
        for (final (i, d) in Domain.values.indexed) ...[
          spec('${d.name}a', d, i * 2),
          spec('${d.name}b', d, i * 2 + 1),
        ],
      ]);
      expect(bp.tabs, hasLength(kMaxTabs));
    });

    test('overrides rename, hide and move, and a moved section stays put', () {
      final sections = [
        spec('m1', Domain.money, 0),
        spec('m2', Domain.money, 1),
        spec('t1', Domain.todo, 2),
        spec('t2', Domain.todo, 3),
        spec('s1', Domain.shopping, 4),
        spec('t3', Domain.todo, 5),
        spec('x', Domain.notes, 6),
      ];
      final bp = layout(sections, {
        'm1': const SectionOverride(title: 'Rent and bills'),
        'x': const SectionOverride(hidden: true),
        's1': const SectionOverride(domain: Domain.shopping),
      });
      expect(bp.sections.map((s) => s.id), isNot(contains('x')));
      expect(bp.sections.first.title, 'Rent and bills');
      expect(bp.tabs.map((t) => t.title), ['Money', 'To-do', 'Shopping']);
    });
  });

  group('JSON', () {
    test('round-trips', () {
      final bp = layout([
        for (final (i, d) in Domain.values.indexed) ...[
          spec('${d.name}a', d, i * 2, type: SectionType.ledger),
          spec('${d.name}b', d, i * 2 + 1),
        ],
      ]);
      final back = Blueprint.fromJson(jsonDecode(jsonEncode(bp.toJson())))!;
      expect(back.tabs.map((t) => t.title), bp.tabs.map((t) => t.title));
      expect(back.sections.toList(), bp.sections.toList());
    });

    test('rejects another format or a newer version', () {
      expect(
        Blueprint.fromJson({'format': 'x', 'version': 1, 'tabs': []}),
        isNull,
      );
      expect(
        Blueprint.fromJson({
          'format': Blueprint.format,
          'version': Blueprint.version + 1,
          'tabs': [],
        }),
        isNull,
      );
      expect(Blueprint.fromJson('nope'), isNull);
    });

    test('drops bad sections, duplicate ids and empty tabs; caps tabs', () {
      final good = spec('ok', Domain.todo, 0).toJson();
      final bp = Blueprint.fromJson({
        'format': Blueprint.format,
        'version': 1,
        'tabs': [
          {
            'title': '',
            'sections': [
              good,
              good, // duplicate id
              {...good, 'id': 'b', 'type': 'hologram'},
              {...good, 'id': ''},
              {...good, 'id': 'c', 'kind': 7},
              {...good, 'id': 'd', 'title': 'x' * 500},
            ],
          },
          {'title': 'Empty', 'sections': []},
          for (var i = 0; i < 10; i++)
            {
              'title': 'T$i',
              'sections': [
                {...good, 'id': 'e$i'},
              ],
            },
        ],
      })!;
      expect(bp.tabs.first.sections.map((s) => s.id), ['ok', 'd']);
      expect(bp.tabs.first.title, 'To-do');
      expect(bp.tabs.first.sections.last.title.length, 80);
      expect(bp.tabs, hasLength(kMaxTabs));
    });
  });
}
