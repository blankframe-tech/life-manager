import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/item.dart';

void main() {
  group('Item.toMap / fromMap round-trip', () {
    test('preserves every synced field', () {
      final original = Item()
        ..uuid = 'abc-123'
        ..kind = ItemKind.deal
        ..title = 'Loan 33k - 600 (parcel)'
        ..note = 'partial'
        ..amount = 33000
        ..direction = DealDirection.iOweThem
        ..section = null
        ..done = false
        ..dueDate = DateTime.utc(2026, 7, 31)
        ..sortOrder = 3
        ..updatedAt = DateTime.utc(2026, 7, 17, 10, 30)
        ..isDeleted = false;

      final restored = Item.fromMap(original.toMap());

      expect(restored.uuid, original.uuid);
      expect(restored.kind, ItemKind.deal);
      expect(restored.title, original.title);
      expect(restored.amount, 33000);
      expect(restored.direction, DealDirection.iOweThem);
      expect(restored.sortOrder, 3);
      expect(restored.updatedAt.toUtc(), original.updatedAt);
      expect(restored.dueDate!.toUtc(), DateTime.utc(2026, 7, 31));
      // Rows coming back from the cloud are, by definition, already synced.
      expect(restored.isSynced, isTrue);
    });

    test('carries the delete tombstone', () {
      final gone = Item()
        ..uuid = 'x'
        ..kind = ItemKind.task
        ..title = 'old'
        ..updatedAt = DateTime.utc(2026, 1, 1)
        ..isDeleted = true;
      expect(Item.fromMap(gone.toMap()).isDeleted, isTrue);
    });
  });

  group('Item.fromSeed', () {
    test('builds a pending, non-deleted local row', () {
      final item = Item.fromSeed(
        {
          'kind': ItemKind.buy,
          'title': 'Going on tour on the 23rd July 5k',
          'section': 'p0',
          'dueDate': '2026-07-23',
        },
        'seed-uuid',
      );
      expect(item.uuid, 'seed-uuid');
      expect(item.kind, ItemKind.buy);
      expect(item.section, 'p0');
      expect(item.dueDate, DateTime.parse('2026-07-23'));
      expect(item.isSynced, isFalse); // must be pushed to the cloud
      expect(item.isDeleted, isFalse);
    });
  });
}
