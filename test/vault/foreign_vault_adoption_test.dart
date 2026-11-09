import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/store/isar_store.dart';
import 'package:life_manager/vault/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/isar_core.dart';

const mine = 'correct horse battery staple';

/// A vault file received from someone else (AirDrop, Files) must only ever be
/// merged: its passphrase never becomes the one protecting this phone's data.
void main() {
  late Directory tmp;
  var n = 0;
  const keychain = FlutterSecureStorage();

  setUpAll(initIsarForTests);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('foreign_vault');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<(Isar, VaultService)> device(String docs) async {
    final dir = Directory('${tmp.path}/$docs')..createSync(recursive: true);
    final isar = await Isar.open([ItemSchema, HistoryEventSchema],
        directory: dir.path, name: 'db${n++}');
    final svc = VaultService(
      IsarStore(isar),
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

  Future<File> received() async {
    final (isar, sender) = await device('sender');
    await isar.writeTxn(() => isar.items.put(Item()
      ..uuid = 'shared'
      ..kind = ItemKind.txn
      ..title = 'shared budget'
      ..updatedAt = DateTime.utc(2026, 10, 1)));
    final file = await sender.saveVault('x');
    // A copy outside the sender's Documents, as an AirDrop open-in would be.
    return file.copySync('${tmp.path}/shared-budget.lmvault');
  }

  test('no vault yet: merges the rows but does not unlock or save', () async {
    final file = await received();
    final (isar, me) = await device('me');

    final report = await me.openVault(file, 'x', remember: true);

    expect(report.itemsAdded, 1, reason: 'the shared rows still merge');
    expect(me.isUnlocked, isFalse);
    expect(await keychain.read(key: 'vault-passphrase'), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await me.exists, isFalse,
        reason: 'nothing may be written under the sender\'s passphrase');
    expect(await isar.items.count(), 1);
  });

  test('locked vault with remember on: keeps my passphrase', () async {
    final file = await received();
    final (_, me) = await device('me');
    await me.saveVault(mine, remember: true);
    await me.lock();

    await me.openVault(file, 'x', remember: true);

    expect(me.isUnlocked, isFalse);
    expect(await keychain.read(key: 'vault-passphrase'), mine);
    expect(await me.unlockFromKeychain(), isTrue,
        reason: 'the next launch must still unlock my own vault');
    expect(me.isUnlocked, isTrue);
  });

  test('opening my own vault file while locked still unlocks it', () async {
    final (_, me) = await device('me');
    await me.saveVault(mine);
    await me.lock();

    await me.openVault(await me.vaultFile, mine);
    expect(me.isUnlocked, isTrue);
  });

  test('a file over 64 MB is rejected before it is read', () async {
    final (_, me) = await device('me');
    final big = File('${tmp.path}/huge.lmvault');
    // Sparse: takes no disk space, but File.length() reports the full size.
    final raf = big.openSync(mode: FileMode.write);
    raf.truncateSync(64 * 1024 * 1024 + 1);
    raf.closeSync();

    await expectLater(
      me.openVault(big, 'x'),
      throwsA(isA<VaultFormatException>()
          .having((e) => e.message, 'message', contains('too large'))),
    );
  });
}
