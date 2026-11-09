import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/backup_service.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:life_manager/store/memory_store.dart';

Item _item(String uuid, {int sort = 0, DateTime? at, bool deleted = false}) =>
    Item()
      ..uuid = uuid
      ..kind = ItemKind.task
      ..title = uuid
      ..sortOrder = sort
      ..isDeleted = deleted
      ..updatedAt = at ?? DateTime.utc(2026, 1, 1);

void main() {
  test('watchItems emits now and on change, sorted, without tombstones',
      () async {
    final store = MemoryStore();
    final seen = <List<String>>[];
    final sub = store
        .watchItems(ItemKind.task)
        .listen((l) => seen.add([for (final i in l) i.uuid]));
    await store.putItems([
      _item('b', sort: 1),
      _item('a', sort: 0, at: DateTime.utc(2026, 1, 1)),
      _item('c', sort: 0, at: DateTime.utc(2026, 2, 1)),
      _item('gone', deleted: true),
    ]);
    await pumpEventQueue();
    expect(seen.first, isEmpty);
    expect(seen.last, ['c', 'a', 'b']);
    await sub.cancel();
  });

  test('rows handed out are copies', () async {
    final store = MemoryStore();
    await store.putItems([_item('a')]);
    final read = (await store.item('a'))!..title = 'changed';
    expect((await store.item('a'))!.title, 'a');
    await store.putItems([read]);
    expect((await store.item('a'))!.title, 'changed');
  });

  test('SyncService.save logs "completed" when done flips', () async {
    final store = MemoryStore();
    final sync = SyncService(store);
    await sync.save(_item('a'));
    final a = (await store.item('a'))!..done = true;
    await sync.save(a);
    expect([for (final h in await store.history()) h.action], [
      'created',
      'completed',
    ]);
    expect(await store.items(synced: false), hasLength(1));
    sync.dispose();
  });

  test('import merges last-write-wins and keeps tombstones', () async {
    final store = MemoryStore();
    await store.putItems([
      _item('old', at: DateTime.utc(2026, 1, 1)),
      _item('new', at: DateTime.utc(2026, 3, 1)),
    ]);
    final other = MemoryStore();
    await other.putItems([
      _item('old', at: DateTime.utc(2026, 2, 1))..title = 'newer',
      _item('new', at: DateTime.utc(2026, 2, 1))..title = 'older',
      _item('dead', deleted: true),
    ]);
    final report = await BackupService(
      store,
    ).importJson(await BackupService(other).buildJson());
    expect(report.itemsAdded, 1);
    expect(report.itemsUpdated, 1);
    expect(report.itemsSkipped, 1);
    expect((await store.item('old'))!.title, 'newer');
    expect((await store.item('new'))!.title, 'new');
    expect((await store.item('dead'))!.isDeleted, isTrue);
  });
}
