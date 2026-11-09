import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:life_manager/vault/vault_codec.dart';
import 'package:life_manager/web/web_vault.dart';

const pass = 'correct horse battery staple';

/// A file the session can re-read (like a Chromium file handle).
class FakeFile implements VaultSource {
  FakeFile(this.bytes);
  Uint8List bytes;
  int modified = 1;
  int writes = 0;

  @override
  String get name => 'LifeManager.lmvault';
  @override
  bool get writesInPlace => true;
  @override
  Future<({Uint8List bytes, int modified})?> readCurrent() async =>
      (bytes: bytes, modified: modified);
  @override
  Future<int?> write(Uint8List b) async {
    bytes = b;
    writes++;
    return ++modified;
  }
}

Future<List<Map<String, dynamic>>> itemsIn(Uint8List file) async {
  final env = VaultCodec.parse(file);
  final key = await VaultCodec.deriveKey(
    pass,
    env.header.salt,
    env.header.iterations,
  );
  final json = jsonDecode(utf8.decode(await VaultCodec.decrypt(env, key)));
  return [for (final i in json['items'] as List) i as Map<String, dynamic>];
}

Item task(String title) => Item()
  ..uuid = 'web-$title'
  ..kind = ItemKind.task
  ..title = title
  ..updatedAt = DateTime.now().toUtc();

void main() {
  final sample = File('test/vault/vectors/sample.lmvault').readAsBytesSync();

  test('wrong passphrase is rejected', () async {
    await expectLater(
      WebVault.open(sample, 'nope', FakeFile(sample), iterations: 1000),
      throwsA(isA<VaultAuthException>()),
    );
  });

  test('opens the sample, edits, syncs, and merges a changed file', () async {
    final file = FakeFile(sample);
    final v = await WebVault.open(sample, pass, file, iterations: 1000);
    expect(await v.store.items(), hasLength(3));
    expect(v.dirty.value, isFalse);

    // Someone (the iPhone) re-saves the file with another salt and an item.
    final other = await WebVault.open(sample, pass, file, iterations: 1000);
    await SyncService(other.store).save(task('from phone'));
    file
      ..bytes = await other.encrypt()
      ..modified = 99;

    await SyncService(v.store).save(task('from web'));
    expect(v.dirty.value, isTrue);
    await v.sync();
    expect(v.dirty.value, isFalse);
    final titles = [for (final i in await itemsIn(file.bytes)) i['title']];
    expect(titles, containsAll(['from web', 'from phone']));
    expect(titles, hasLength(5));

    // Fresh nonce on every write.
    final a = VaultCodec.parse(await v.encrypt()).header.nonce;
    final b = VaultCodec.parse(await v.encrypt()).header.nonce;
    expect(a, isNot(equals(b)));

    v.dispose();
    other.dispose();
    expect(v.isLocked, isTrue);
  });

  test('an unreadable changed file blocks the write', () async {
    final file = FakeFile(sample);
    final v = await WebVault.open(sample, pass, file, iterations: 1000);
    final stranger = await WebVault.create('another passphrase', file,
        iterations: 1000);
    file
      ..bytes = await stranger.encrypt()
      ..modified = 42;
    await expectLater(v.sync(), throwsA(isA<VaultAuthException>()));
    expect(file.writes, 0);
    v.dispose();
    stranger.dispose();
  });

  test('create needs 10 characters', () async {
    expect(
      () => WebVault.create('short', FakeFile(sample), iterations: 1000),
      throwsArgumentError,
    );
  });
}
