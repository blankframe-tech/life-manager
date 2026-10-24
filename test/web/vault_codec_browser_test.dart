@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/services/sync_service.dart';
import 'package:life_manager/vault/vault_codec.dart';
import 'package:life_manager/web/web_vault.dart';

import '../vault/vectors/embedded.dart';

// Run with: flutter test --platform chrome test/web
// The same vectors as test/vault/vault_codec_test.dart, through the browser's
// WebCrypto backend of the `cryptography` package.

Uint8List vector(String name) => base64.decode(embeddedVectors[name]!);

class _Download implements VaultSource {
  Uint8List? last;
  @override
  String get name => 'LifeManager.lmvault';
  @override
  bool get writesInPlace => false;
  @override
  Future<({Uint8List bytes, int modified})?> readCurrent() async => null;
  @override
  Future<int?> write(Uint8List bytes) async {
    last = bytes;
    return null;
  }
}

void main() {
  test('uses WebCrypto', () {
    expect(Cryptography.instance, isA<BrowserCryptography>());
  });

  for (final name in [
    'ascii_small.json',
    'unicode_backup.json',
    'nfd_passphrase.json',
  ]) {
    test('vector $name: key, byte-exact file, plaintext', () async {
      final v = jsonDecode(utf8.decode(vector(name))) as Map<String, dynamic>;
      final expected = base64.decode(v['file'] as String);
      final env = VaultCodec.parse(expected);
      expect(jsonEncode(env.header.toJson()), v['headerJson']);
      final key = await VaultCodec.deriveKey(
        v['passphrase'] as String,
        base64.decode(v['salt'] as String),
        v['iterations'] as int,
      );
      expect(base64.encode(key), v['derivedKey']);
      final rebuilt = await VaultCodec.encrypt(
        plaintext: utf8.encode(v['plaintext'] as String),
        key: key,
        header: env.header,
      );
      expect(rebuilt, expected);
      expect(utf8.decode(await VaultCodec.decrypt(env, key)), v['plaintext']);
    });
  }

  test('sample.lmvault: wrong passphrase fails, right one opens', () async {
    final sample = vector('sample.lmvault');
    final out = _Download();
    await expectLater(
      WebVault.open(sample, 'wrong', out),
      throwsA(isA<VaultAuthException>()),
    );
    final v = await WebVault.open(sample, 'correct horse battery staple', out);
    expect(await v.store.items(), hasLength(3));

    await SyncService(v.store).save(
      Item()
        ..uuid = 'browser-task'
        ..kind = ItemKind.task
        ..title = 'Added in the browser'
        ..updatedAt = DateTime.now().toUtc(),
    );
    await v.sync();
    final env = VaultCodec.parse(out.last!);
    expect(env.header.iterations, VaultCodec.defaultIterations);
    final key = await VaultCodec.deriveKey(
      'correct horse battery staple',
      env.header.salt,
      env.header.iterations,
    );
    final json = utf8.decode(await VaultCodec.decrypt(env, key));
    expect(json, contains('Added in the browser'));
    v.dispose();
  });

  test('a flipped ciphertext byte fails authentication', () async {
    final v = jsonDecode(utf8.decode(vector('ascii_small.json')));
    final file = base64.decode(v['file'] as String);
    final key = base64.decode(v['derivedKey'] as String);
    final bad = Uint8List.fromList(file)..[file.length - 20] ^= 1;
    await expectLater(
      VaultCodec.decrypt(VaultCodec.parse(bad), key),
      throwsA(isA<VaultAuthException>()),
    );
  });
}
