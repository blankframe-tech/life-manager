import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/canvas/blueprint.dart';
import 'package:life_manager/canvas/shaper.dart';
import 'package:life_manager/models/item.dart';

import 'fixtures.dart';

/// Sunday 1 Nov 2026.
final now = DateTime(2026, 11, 1, 10);

CompiledSource shape(String text, {String name = 'Pasted note'}) =>
    Shaper.compile(SourceDoc(name, text), now: now);

List<Item> itemsIn(CompiledSource c, String sectionTitle) {
  final s = c.sections.firstWhere((s) => s.title == sectionTitle);
  return c.items.where((i) => i.section == s.id).toList();
}

SectionSpec section(CompiledSource c, String title) =>
    c.sections.firstWhere((s) => s.title == title);

void main() {
  group('one big pinned Keep note', () {
    final c = shape(keepNote, name: 'Keep');

    test('every heading becomes a section, in the order written', () {
      expect(c.sections.map((s) => s.title), [
        'Monthly budget',
        'Dena paona',
        'Bazaar list',
        'TODO',
        'Dreams',
        'Random thoughts',
      ]);
    });

    test('each section gets the right shape and storage kind', () {
      expect(section(c, 'Monthly budget').type, SectionType.ledger);
      expect(section(c, 'Monthly budget').kind, ItemKind.budget);
      expect(section(c, 'Dena paona').type, SectionType.people);
      expect(section(c, 'Bazaar list').kind, ItemKind.buy);
      expect(section(c, 'TODO').kind, ItemKind.task);
      expect(section(c, 'Dreams').type, SectionType.goals);
      expect(section(c, 'Random thoughts').type, SectionType.notes);
    });

    test('amounts read 10k, 1.5 lakh, ৳1,500 and Bangla digits', () {
      final budget = itemsIn(c, 'Monthly budget');
      expect(budget.map((i) => i.amount), [18000, 150000, 1500, 2500, 5000]);
      expect(budget.first.title, 'Rent');
      expect(budget.map((i) => i.category), [
        BudgetCategory.needs,
        BudgetCategory.savings,
        BudgetCategory.needs,
        BudgetCategory.needs,
        BudgetCategory.wants,
      ]);
    });

    test('who owes whom, and how much', () {
      final deals = itemsIn(c, 'Dena paona');
      expect(deals.map((d) => d.title), ['Rahim', 'Karim', 'Sabbir', 'Mitu']);
      expect(deals.map((d) => d.direction), [
        DealDirection.theyOweMe,
        DealDirection.iOweThem,
        DealDirection.theyOweMe,
        DealDirection.iOweThem,
      ]);
      expect(deals.map((d) => d.amount), [500, 300, 2000, 1200]);
      expect(deals.first.note, 'Rahim owes me 500');
    });

    test('checklist ticks, prices and dates', () {
      final bazaar = itemsIn(c, 'Bazaar list');
      expect(bazaar.map((i) => i.title), ['Eggs', 'Rice 5kg', 'Soap']);
      expect(bazaar.map((i) => i.done), [false, true, false]);
      expect(bazaar.first.amount, 150);

      final todo = itemsIn(c, 'TODO');
      expect(todo[0].title, 'Call the landlord');
      expect(todo[0].dueDate, DateTime(2026, 11, 2));
      expect(todo[1].title, 'Renew passport');
      expect(todo[1].dueDate, DateTime(2026, 12, 15));
      expect(todo[2].title, "Fix the bike's chain");
      expect(todo[2].dueDate, DateTime(2026, 11, 6)); // next Friday
      expect(todo[3].title, 'Book the wedding hall');
      expect(todo[3].dueDate, isNull, reason: '"wedding" is not Wednesday');
    });

    test('a year is not a price, and notes keep the words as written', () {
      final dreams = itemsIn(c, 'Dreams');
      expect(dreams.first.title, 'Visit Japan 2027');
      expect(dreams.first.amount, isNull);
      final note = itemsIn(c, 'Random thoughts').single;
      expect(note.kind, ItemKind.note);
      expect(note.note, contains('Maybe start running'));
    });
  });

  test('a WhatsApp chat with yourself is sorted line by line', () {
    final c = shape(whatsAppChat, name: 'WhatsApp Chat with Me.txt');
    final byKind = {for (final s in c.sections) s.kind: s};
    expect(
      byKind.keys,
      containsAll([ItemKind.deal, ItemKind.txn, ItemKind.task]),
    );
    final all = c.items.map((i) => i.title).join(' | ');
    expect(all, isNot(contains('PM]')), reason: 'chat prefixes are stripped');
    expect(all, isNot(contains('encrypted')));
    final lunch = c.items.firstWhere((i) => i.title == 'lunch');
    expect(lunch.dueDate, DateTime(2026, 10, 11), reason: 'sent that day');
    final deal = c.items.firstWhere((i) => i.kind == ItemKind.deal);
    expect(deal.title, 'Tanvir');
    expect(deal.amount, 800);
    expect(
      c.items.where((i) => i.kind == ItemKind.buy).map((i) => i.title),
      contains('buy milk'),
    );
  });

  test('a budget sheet saved as CSV becomes a dated money log', () {
    final c = shape(budgetCsv, name: 'Budget 2026.csv');
    final s = c.sections.single;
    expect(s.title, 'Budget 2026');
    expect(s.kind, ItemKind.txn);
    expect(s.type, SectionType.ledger);
    expect(c.items, hasLength(4));
    final salary = c.items.firstWhere((i) => i.title == 'Salary');
    expect(salary.direction, TxnDirection.earn);
    expect(salary.amount, 60000);
    final rent = c.items.firstWhere((i) => i.title == 'Rent');
    expect(rent.direction, TxnDirection.spend);
    expect(rent.amount, 18000);
    expect(rent.dueDate, DateTime(2026, 10, 1));
    expect(rent.category, 'Housing');
    expect(rent.note, 'Paid by: bKash', reason: 'unknown columns are kept');
  });

  test('a bank export with signed amounts reads money in and out', () {
    final c = shape(
      'Date,Description,Amount\n2026-10-02,ATM,-2000\n2026-10-03,Refund,350\n',
      name: 'statement.csv',
    );
    expect(c.items.map((i) => i.direction), [
      TxnDirection.spend,
      TxnDirection.earn,
    ]);
    expect(c.items.map((i) => i.amount), [2000, 350]);
  });

  test('a CSV without numbers becomes a checklist', () {
    final c = shape(
      'Task,Done\nPay school fees,yes\nBuy shoes,no\n',
      name: 'list.csv',
    );
    expect(c.sections.single.kind, ItemKind.task);
    expect(c.items.map((i) => i.done), [true, false]);
  });

  test('commas in pasted text do not make a table', () {
    final c = shape('Rice, eggs, oil\nMilk, bread, jam\nSalt, sugar, tea');
    expect(c.sections.single.type, SectionType.checklist);
    expect(c.items, hasLength(3));
  });

  test('handwritten goals in sentences become a note', () {
    final c = shape(
      'I want to be debt free by the end of next year and finally take Ma '
      'to Cox\'s Bazar.\nAlso learn to swim properly this winter.',
    );
    expect(c.sections.single.type, SectionType.notes);
  });

  test('an empty heading still reserves a place', () {
    final c = shape('Shopping list:\n\nNotes:\nsomething to remember');
    expect(c.sections.map((s) => s.kind), [ItemKind.buy, ItemKind.note]);
    expect(c.items, hasLength(1));
  });

  test('nothing in, nothing out', () {
    final c = shape('   \n\n  ');
    expect(c.sections, isEmpty);
    expect(c.items, isEmpty);
  });

  test('deterministic: same text, same ids, any line endings', () {
    final a = shape(keepNote);
    final b = shape(keepNote.replaceAll('\n', '\r\n'));
    expect(a.hash, b.hash);
    expect(a.sections, b.sections);
    expect(a.items.map((i) => i.uuid), b.items.map((i) => i.uuid));
    expect(a.items.map((i) => i.uuid).toSet(), hasLength(a.items.length));
  });

  test('order base places a later source after earlier ones', () {
    final c = Shaper.compile(
      const SourceDoc('x', 'TODO\n- a'),
      orderBase: 3 * kOrderStride,
    );
    expect(c.sections.single.order, 3000);
  });

  test('quick add parses one line for its section', () {
    final deals = SectionSpec(
      id: 's1',
      title: 'Dena paona',
      type: SectionType.people,
      kind: ItemKind.deal,
      domain: Domain.people,
      order: 0,
    );
    final i = Shaper.quickItem('lent 700 to Nadia', deals, now: now);
    expect(i.section, 's1');
    expect(i.title, 'Nadia');
    expect(i.amount, 700);
    expect(i.direction, DealDirection.theyOweMe);
  });

  test('route sends a jotted line to the section it fits', () {
    final c = shape(keepNote);
    expect(Shaper.route('Arif owes me 200', c.sections)!.kind, ItemKind.deal);
    expect(Shaper.route('call the bank', c.sections)!.kind, ItemKind.task);
    expect(Shaper.route('buy batteries', c.sections)!.kind, ItemKind.buy);
    expect(Shaper.route('anything', []), isNull);
  });
}
