import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/vault/vault_codec.dart';

const pass = 'correct horse battery staple';

VaultHeader header({int iterations = 1000}) => VaultHeader(
      iterations: iterations,
      salt: Uint8List.fromList(List.generate(16, (i) => i)),
      nonce: Uint8List.fromList(List.generate(12, (i) => 0xa0 + i)),
      createdAt: DateTime.utc(2026, 10, 24),
      updatedAt: DateTime.utc(2026, 10, 24, 1),
      deviceId: 'test',
    );

Future<Uint8List> open(List<int> bytes, String passphrase) async {
  final env = VaultCodec.parse(bytes);
  final key = await VaultCodec.deriveKey(
      passphrase, env.header.salt, env.header.iterations);
  return VaultCodec.decrypt(env, key);
}

void main() {
  late Uint8List file;
  final plaintext = utf8.encode('{"format":"life-manager-backup","items":[]}');

  setUpAll(() async {
    final h = header();
    file = await VaultCodec.encrypt(
      plaintext: plaintext,
      key: await VaultCodec.deriveKey(pass, h.salt, h.iterations),
      header: h,
    );
  });

  test('round trip', () async {
    expect(await open(file, pass), plaintext);
    final env = VaultCodec.parse(file);
    expect(env.header.deviceId, 'test');
    expect(env.header.iterations, 1000);
  });

  test('wrong passphrase fails with VaultAuthException', () async {
    await expectLater(open(file, 'wrong'), throwsA(isA<VaultAuthException>()));
  });

  group('a flipped byte fails', () {
    final headerLen = () => ByteData.sublistView(file, 4, 8).getUint32(0);
    Uint8List flip(int i) => Uint8List.fromList(file)..[i] ^= 0x01;

    test('magic', () {
      expect(() => VaultCodec.parse(flip(0)),
          throwsA(isA<VaultFormatException>()));
    });

    test('header JSON (deviceId) → auth failure', () async {
      final i = latin1.decode(file).indexOf('"test"') + 1;
      await expectLater(open(flip(i), pass), throwsA(isA<VaultAuthException>()));
    });

    test('nonce', () async {
      // Flip a byte inside the base64 nonce; stays valid base64 of 12 bytes.
      final text = latin1.decode(file);
      final start = text.indexOf('"nonce":"') + 9;
      final bytes = Uint8List.fromList(file)..[start] = 'b'.codeUnitAt(0);
      expect(bytes, isNot(file));
      expect(VaultCodec.parse(bytes).header.nonce, isNot(header().nonce));
      await expectLater(open(bytes, pass), throwsA(isA<VaultAuthException>()));
    });

    test('ciphertext', () async {
      await expectLater(
          open(flip(8 + headerLen() + 2), pass), throwsA(isA<VaultAuthException>()));
    });

    test('tag', () async {
      await expectLater(
          open(flip(file.length - 1), pass), throwsA(isA<VaultAuthException>()));
    });

    test('every single byte', () async {
      // Exhaustive: no flipped byte ever yields plaintext.
      final key = await VaultCodec.deriveKey(pass, header().salt, 1000);
      for (var i = 0; i < file.length; i++) {
        final env = () {
          try {
            return VaultCodec.parse(flip(i));
          } on VaultException {
            return null;
          }
        }();
        if (env == null) continue;
        final k = listEquals(env.header.salt, header().salt) &&
                env.header.iterations == 1000
            ? key
            : await VaultCodec.deriveKey(
                pass, env.header.salt, env.header.iterations);
        await expectLater(VaultCodec.decrypt(env, k),
            throwsA(isA<VaultException>()), reason: 'byte $i');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test('truncated and non-vault files fail with VaultFormatException', () {
    expect(() => VaultCodec.parse([1, 2, 3]),
        throwsA(isA<VaultFormatException>()));
    expect(() => VaultCodec.parse(file.sublist(0, 40)),
        throwsA(isA<VaultFormatException>()));
    expect(() => VaultCodec.parse(utf8.encode('{"format":"x"}')),
        throwsA(isA<VaultFormatException>()));
  });

  group('vectors', () {
    for (final name in ['ascii_small', 'unicode_backup']) {
      final f = File('test/vault/vectors/$name.json');
      test(name, () async {
        final v = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        final expected = base64.decode(v['file'] as String);
        final env = VaultCodec.parse(expected);
        expect(jsonEncode(env.header.toJson()), v['headerJson']);

        final key = await VaultCodec.deriveKey(v['passphrase'] as String,
            base64.decode(v['salt'] as String), v['iterations'] as int);
        expect(base64.encode(key), v['derivedKey']);

        final rebuilt = await VaultCodec.encrypt(
            plaintext: utf8.encode(v['plaintext'] as String),
            key: key,
            header: env.header);
        expect(rebuilt, expected);
        expect(utf8.decode(await VaultCodec.decrypt(env, key)), v['plaintext']);
      });
    }
  });

  test('sample.lmvault opens with the documented passphrase', () async {
    final bytes = File('test/vault/vectors/sample.lmvault').readAsBytesSync();
    final env = VaultCodec.parse(bytes);
    expect(env.header.iterations, VaultCodec.defaultIterations);
    final json = jsonDecode(utf8.decode(await open(bytes, pass))) as Map;
    expect(json['format'], 'life-manager-backup');
    expect((json['items'] as List).length, 3);
  });
}
