import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/reset_service.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:life_manager/store/isar_store.dart';
import 'package:life_manager/vault/vault_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/isar_core.dart';

/// "Delete all data" promises to erase everything on this device. The vault
/// file and its remembered passphrase are part of that, or the next launch
/// silently merges everything back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(initIsarForTests);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('reset_vault');
    // SeedLoader.markSeeded writes its marker to Application Support.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('wipe deletes the vault file and forgets the passphrase', () async {
    final docs = Directory('${tmp.path}/docs')..createSync();
    final isar = await Isar.open([ItemSchema, HistoryEventSchema],
        directory: docs.path, name: 'reset');
    final store = IsarStore(isar);
    final prefs = await SharedPreferences.getInstance();
    VaultService vault() => VaultService(
          store,
          prefs: prefs,
          documentsDir: () async => docs,
          iterations: 1000, // shortcut: test speed only; app default is 600k
          autoSaveDelay: const Duration(milliseconds: 50),
        );
    final svc = vault();
    addTearDown(() async {
      svc.dispose();
      await isar.close(deleteFromDisk: true);
    });

    await isar.writeTxn(() => isar.items.put(Item()
      ..uuid = 's'
      ..kind = ItemKind.note
      ..title = 'secret to erase'
      ..updatedAt = DateTime.utc(2026, 10, 1)));
    final file = await svc.saveVault('correct horse battery', remember: true);
    File('${file.path}.tmp').writeAsStringSync('half-written');
    await svc.lock();

    final sync = SyncService(store);
    addTearDown(sync.dispose);
    await ResetService(store, prefs, sync, vault: svc).wipeEverything();

    expect(await isar.items.count(), 0);
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    expect(await const FlutterSecureStorage().read(key: 'vault-passphrase'),
        isNull);

    // Next launch: a fresh service over the same Documents.
    final relaunch = vault();
    addTearDown(relaunch.dispose);
    expect(await relaunch.unlockFromKeychain(), isFalse);
    expect(await isar.items.count(), 0);
  });

  test('wipe while unlocked stops auto-save from writing a new file',
      () async {
    final docs = Directory('${tmp.path}/docs')..createSync();
    final isar = await Isar.open([ItemSchema, HistoryEventSchema],
        directory: docs.path, name: 'reset2');
    final store = IsarStore(isar);
    final svc = VaultService(
      store,
      prefs: await SharedPreferences.getInstance(),
      documentsDir: () async => docs,
      iterations: 1000,
      autoSaveDelay: const Duration(milliseconds: 50),
    );
    addTearDown(() async {
      svc.dispose();
      await isar.close(deleteFromDisk: true);
    });
    final file = await svc.saveVault('correct horse battery');
    final sync = SyncService(store);
    addTearDown(sync.dispose);

    await ResetService(store, await SharedPreferences.getInstance(), sync,
            vault: svc)
        .wipeEverything();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(svc.isUnlocked, isFalse);
    expect(file.existsSync(), isFalse);
  });
}
