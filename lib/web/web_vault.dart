import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/backup_service.dart';
import '../store/memory_store.dart';
import '../vault/vault_codec.dart';

/// Where the vault file lives for a web session. Browser implementations are
/// in `browser.dart`; tests use a fake.
abstract class VaultSource {
  /// File name shown in the bar ("LifeManager.lmvault").
  String get name;

  /// True when [write] replaces the opened file (File System Access API).
  /// False when it downloads a copy for the user to put back.
  bool get writesInPlace;

  /// The file as it is now, or null when it can't be re-read (download-only).
  Future<({Uint8List bytes, int modified})?> readCurrent();

  /// Writes [bytes]. Returns the file's new modified time when known.
  Future<int?> write(Uint8List bytes);
}

/// One unlocked vault in the browser: the decrypted rows (in a [MemoryStore]),
/// the derived key, and the file it came from. Nothing here is persisted;
/// [dispose] drops it all.
///
/// Byte-compatible with docs/VAULT_FORMAT.md through [VaultCodec], which uses
/// the `cryptography` package's WebCrypto backend in the browser.
class WebVault {
  WebVault._(
    this.store,
    this.source, {
    required String this._passphrase,
    required Uint8List this._key,
    required this._salt,
    required this._createdAt,
    required int? modified,
    required this.iterations,
  }) : _knownModified = modified {
    _changes = store.changes.listen((_) {
      _revision++;
      dirty.value = true;
    });
  }

  final MemoryStore store;
  VaultSource source;
  final int iterations;

  /// Unsynced changes since the last successful [sync].
  final dirty = ValueNotifier<bool>(false);
  final lastSyncedAt = ValueNotifier<DateTime?>(null);

  // Kept for the session so a file re-saved by the iPhone (which picks a new
  // salt on every unlock) can be decrypted and merged before we overwrite it.
  String? _passphrase;
  Uint8List? _key;
  final Uint8List _salt;
  final DateTime _createdAt;
  int? _knownModified;
  int _revision = 0;
  late final StreamSubscription<void> _changes;
  Future<void> _queue = Future.value();

  /// This browser session, as the header's `deviceId`.
  final _deviceId = 'web-${const Uuid().v4()}';
  static final _random = Random.secure();

  static const minPassphraseLength = 10;

  /// Decrypts [bytes] and loads them. Throws [VaultAuthException] on a wrong
  /// passphrase (or a modified file) and [VaultFormatException] on a file
  /// that isn't a readable vault.
  static Future<WebVault> open(
    Uint8List bytes,
    String passphrase,
    VaultSource source, {
    int? modified,
    int iterations = VaultCodec.defaultIterations,
  }) async {
    final env = VaultCodec.parse(bytes);
    final h = env.header;
    var key = await VaultCodec.deriveKey(passphrase, h.salt, h.iterations);
    final plain = await VaultCodec.decrypt(env, key);
    final store = MemoryStore();
    await BackupService(store).importJson(utf8.decode(plain));
    var salt = h.salt;
    // Never write a weaker KDF setting than the spec's (test vectors use 1k).
    if (h.iterations != iterations) {
      salt = _bytes(VaultCodec.saltLength);
      key = await VaultCodec.deriveKey(passphrase, salt, iterations);
    }
    return WebVault._(
      store,
      source,
      passphrase: passphrase,
      key: key,
      salt: salt,
      createdAt: h.createdAt,
      modified: modified,
      iterations: iterations,
    );
  }

  /// A new, empty vault. It exists only in memory until the first [sync].
  static Future<WebVault> create(
    String passphrase,
    VaultSource source, {
    int iterations = VaultCodec.defaultIterations,
  }) async {
    if (passphrase.length < minPassphraseLength) {
      throw ArgumentError('Use at least $minPassphraseLength characters.');
    }
    final salt = _bytes(VaultCodec.saltLength);
    final v = WebVault._(
      MemoryStore(),
      source,
      passphrase: passphrase,
      key: await VaultCodec.deriveKey(passphrase, salt, iterations),
      salt: salt,
      createdAt: DateTime.now().toUtc(),
      modified: null,
      iterations: iterations,
    );
    v.dirty.value = true;
    return v;
  }

  bool get isLocked => _key == null;

  /// Re-encrypts with a fresh nonce and writes through [source]. If the file
  /// changed since we loaded or last wrote it, it is decrypted and merged
  /// first (last-write-wins, as `VaultService` does); if it can't be
  /// decrypted, this throws and nothing is written.
  Future<void> sync() => _serial(() async {
    if (isLocked) throw StateError('Vault is locked.');
    final current = await source.readCurrent();
    if (current != null && current.modified != _knownModified) {
      await _merge(current.bytes);
      _knownModified = current.modified;
    }
    final revision = _revision;
    final bytes = await encrypt();
    _knownModified = await source.write(bytes) ?? _knownModified;
    lastSyncedAt.value = DateTime.now();
    if (_revision == revision) dirty.value = false;
  });

  /// The whole vault as a file: a fresh random nonce on every call.
  Future<Uint8List> encrypt() async => VaultCodec.encrypt(
    plaintext: utf8.encode(await BackupService(store).buildJson()),
    key: _key!,
    header: VaultHeader(
      iterations: iterations,
      salt: _salt,
      nonce: _bytes(VaultCodec.nonceLength),
      createdAt: _createdAt,
      updatedAt: DateTime.now().toUtc(),
      deviceId: _deviceId,
    ),
  );

  Future<void> _merge(Uint8List bytes) async {
    final env = VaultCodec.parse(bytes);
    final h = env.header;
    final key = h.iterations == iterations && listEquals(h.salt, _salt)
        ? _key!
        : await VaultCodec.deriveKey(_passphrase!, h.salt, h.iterations);
    final plain = await VaultCodec.decrypt(env, key);
    await BackupService(store).importJson(utf8.decode(plain));
  }

  /// Locks: drops the key, the passphrase and every decrypted row. Dart can't
  /// wipe an immutable String, so the passphrase is released to the GC; the
  /// key bytes are zeroed first.
  void dispose() {
    _changes.cancel();
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _passphrase = null;
    store.dispose();
    dirty.dispose();
    lastSyncedAt.dispose();
  }

  static Uint8List _bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
