import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/vault/vault_codec.dart';
import 'package:life_manager/vault/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/isar_core.dart';

const pass = 'correct horse battery staple';

Item item(String uuid, String title, DateTime updatedAt) => Item()
  ..uuid = uuid
  ..kind = ItemKind.task
  ..title = title
  ..updatedAt = updatedAt;

void main() {
  late Directory tmp;
  var n = 0;

  setUpAll(() async {
    await initIsarForTests();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('vault_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(Isar, VaultService)> device(String docs) async {
    final dir = Directory('${tmp.path}/$docs')..createSync(recursive: true);
    final isar = await Isar.open([ItemSchema, HistoryEventSchema],
        directory: dir.path, name: 'db${n++}');
    final svc = VaultService(
      isar,
      prefs: await SharedPreferences.getInstance(),
      documentsDir: () async => dir,
      iterations: 1000, // shortcut: test speed only; app default is 600k
      autoSaveDelay: const Duration(milliseconds: 50),
    );
    addTearDown(() async {
      svc.dispose();
      await isar.close(deleteFromDisk: true);
    });
    return (isar, svc);
  }

  Future<void> put(Isar isar, Item i) => isar.writeTxn(() => isar.items.put(i));

  test('save then open on another device round-trips', () async {
    final (a, va) = await device('a');
    await put(a, item('x', 'Renew passport', DateTime.utc(2026, 10, 1)));
    final file = await va.saveVault(pass);
    expect(file.path, endsWith('/LifeManager.lmvault'));

    final (b, vb) = await device('b');
    final report = await vb.openVault(file, pass);
    expect(report.itemsAdded, 1);
    expect((await b.items.where().findAll()).single.title, 'Renew passport');
    expect(vb.isUnlocked, isTrue);
  });

  test('open with the wrong passphrase fails and imports nothing', () async {
    final (a, va) = await device('a');
    await put(a, item('x', 'T', DateTime.utc(2026, 10, 1)));
    final file = await va.saveVault(pass);

    final (b, vb) = await device('b');
    await expectLater(
        vb.openVault(file, 'nope'), throwsA(isA<VaultAuthException>()));
    expect(await b.items.count(), 0);
    expect(vb.isUnlocked, isFalse);
  });

  test('merge on open keeps newer local edits', () async {
    final (a, va) = await device('a');
    await put(a, item('x', 'old title', DateTime.utc(2026, 10, 1)));
    await put(a, item('y', 'only in vault', DateTime.utc(2026, 10, 1)));
    final file = await va.saveVault(pass);

    final (b, vb) = await device('b');
    await put(b, item('x', 'newer local title', DateTime.utc(2026, 10, 5)));
    final report = await vb.openVault(file, pass);

    expect(report.itemsSkipped, 1);
    expect(report.itemsAdded, 1);
    final x = await b.items.filter().uuidEqualTo('x').findFirst();
    expect(x!.title, 'newer local title');
    expect(await b.items.filter().uuidEqualTo('y').findFirst(), isNotNull);
  });

  test('saveVault merges an existing vault before overwriting it', () async {
    final (a, va) = await device('shared');
    await put(a, item('web', 'edited in the browser', DateTime.utc(2026, 10, 9)));
    await va.saveVault(pass);
    await va.lock();

    // Same Documents dir, fresh DB: the file holds data this DB lacks.
    final (b, vb) = await device('shared');
    await vb.saveVault(pass);
    expect((await b.items.where().findAll()).single.title,
        'edited in the browser');
  });

  test('saveVault refuses to overwrite a vault it cannot decrypt', () async {
    final (_, va) = await device('shared');
    final file = await va.saveVault(pass);
    final before = file.readAsBytesSync();

    final (_, vb) = await device('shared');
    await expectLater(
        vb.saveVault('different'), throwsA(isA<VaultAuthException>()));
    expect(vb.isUnlocked, isFalse);
    expect(file.readAsBytesSync(), before);

    await vb.saveVault('different', replaceExisting: true);
    expect(file.readAsBytesSync(), isNot(before));
  });

  test('changePassphrase re-encrypts under the new one only', () async {
    final (a, va) = await device('a');
    await put(a, item('x', 'T', DateTime.utc(2026, 10, 1)));
    await va.saveVault(pass);
    await expectLater(
        va.changePassphrase('wrong', 'new pass'), throwsA(isA<VaultAuthException>()));
    final file = await va.changePassphrase(pass, 'new pass');

    final (_, vb) = await device('b');
    await expectLater(vb.openVault(file, pass), throwsA(isA<VaultAuthException>()));
    expect((await vb.openVault(file, 'new pass')).itemsAdded, 1);
  });

  test('remember keeps the passphrase in the keychain only', () async {
    final (_, va) = await device('a');
    final file = await va.saveVault(pass, remember: true);
    expect(latin1.decode(file.readAsBytesSync()), isNot(contains(pass)));
    await va.lock();
    expect(va.isUnlocked, isFalse);
    expect(await va.unlockFromKeychain(), isTrue);
    expect(va.isUnlocked, isTrue);
    await va.lock(forget: true);
    expect(await va.unlockFromKeychain(), isFalse);
  });

  test('auto-saves after changes once unlocked', () async {
    final (a, va) = await device('a');
    final file = await va.saveVault(pass);
    await put(a, item('later', 'added after unlock', DateTime.utc(2026, 10, 2)));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final env = VaultCodec.parse(file.readAsBytesSync());
    final key = await VaultCodec.deriveKey(pass, env.header.salt, 1000);
    final json = utf8.decode(await VaultCodec.decrypt(env, key));
    expect(json, contains('added after unlock'));
    expect(va.lastError.value, isNull);
  });

  test('an atomic write that throws leaves the old file intact', () async {
    final target = File('${tmp.path}/LifeManager.lmvault')
      ..writeAsStringSync('old vault');
    // A directory squatting on the temp path makes the write itself fail.
    Directory('${target.path}.tmp').createSync();
    await expectLater(writeAtomically(target, [1, 2, 3]),
        throwsA(isA<FileSystemException>()));
    expect(target.readAsStringSync(), 'old vault');

    Directory('${target.path}.tmp').deleteSync();
    await writeAtomically(target, utf8.encode('new vault'));
    expect(target.readAsStringSync(), 'new vault');
    expect(File('${target.path}.tmp').existsSync(), isFalse);
  });
}
