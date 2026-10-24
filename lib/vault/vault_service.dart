import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/backup_service.dart';
import '../store/local_store.dart';
import 'vault_codec.dart';

export 'vault_codec.dart'
    show VaultException, VaultFormatException, VaultAuthException;

/// Keeps everything in one encrypted file, `Documents/LifeManager.lmvault`,
/// which iOS shows in Files › On My iPhone › Life Manager.
///
/// The plaintext inside is exactly [BackupService.buildJson], and opening a
/// vault merges through [BackupService.importJson] — the same last-write-wins
/// rule as sync and JSON import.
///
/// The passphrase is held in memory for the session (plus the derived key, so
/// auto-saves don't re-run 600k PBKDF2 rounds). With `remember: true` it is
/// also written to the iOS Keychain, never to a plain file.
class VaultService {
  VaultService(
    this.store, {
    required this.prefs,
    BackupService? backup,
    Future<Directory> Function()? documentsDir,
    FlutterSecureStorage? keychain,
    this.iterations = VaultCodec.defaultIterations,
    this.autoSaveDelay = const Duration(seconds: 2),
  }) : backup = backup ?? BackupService(store),
       _documentsDir = documentsDir ?? getApplicationDocumentsDirectory,
       _keychain = keychain ?? _defaultKeychain;

  static const fileName = 'LifeManager.lmvault';
  static const _keychainKey = 'vault-passphrase';
  static const _deviceIdKey = 'vault.deviceId';

  // Same Keychain settings as secure_session_storage: never leaves the device.
  static const _defaultKeychain = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
  );

  final LocalStore store;
  final SharedPreferences prefs;
  final BackupService backup;
  final int iterations;
  final Duration autoSaveDelay;
  final Future<Directory> Function() _documentsDir;
  final FlutterSecureStorage _keychain;

  /// When the vault file was last written by this session.
  final lastSavedAt = ValueNotifier<DateTime?>(null);

  /// The last auto-save failure, cleared by the next successful save. Auto-save
  /// runs unattended, so this is the only place its errors surface.
  final lastError = ValueNotifier<Object?>(null);

  String? _passphrase;
  Uint8List? _salt;
  Uint8List? _key;
  DateTime? _createdAt;

  /// mtime of the file as we last wrote or merged it. A different mtime means
  /// someone replaced it (Files app, iCloud) and it must be merged first.
  DateTime? _knownModified;

  Timer? _debounce;
  final _subs = <StreamSubscription<void>>[];
  Future<void> _queue = Future.value();
  final _random = Random.secure();

  /// True once a passphrase is set for this session; auto-save is on.
  bool get isUnlocked => _passphrase != null;

  /// [isUnlocked] as a listenable, for the Settings status row.
  final unlocked = ValueNotifier<bool>(false);

  /// Whether `LifeManager.lmvault` exists yet.
  Future<bool> get exists async => (await vaultFile).exists();

  Future<File> get vaultFile async =>
      File('${(await _documentsDir()).path}/$fileName');

  /// Sets the session passphrase (first call) and writes the vault now.
  ///
  /// If a vault already exists it is merged in first, so edits made elsewhere
  /// (the web app) survive. If it can't be decrypted with [passphrase] this
  /// throws [VaultAuthException] and changes nothing — pass [replaceExisting]
  /// to discard that file on purpose. Once unlocked, a different passphrase
  /// throws [StateError]: use [changePassphrase].
  Future<File> saveVault(
    String passphrase, {
    bool remember = false,
    bool replaceExisting = false,
  }) => _serial(() async {
    _checkPassphrase(passphrase);
    if (isUnlocked) {
      if (passphrase != _passphrase) {
        throw StateError('Vault is unlocked; use changePassphrase.');
      }
      return _write();
    }
    _knownModified = null;
    // Verify + merge before touching session state.
    if (replaceExisting) {
      _knownModified = await _modified();
    } else {
      await _merge(passphrase);
    }
    await _startSession(passphrase, remember: remember);
    return _write(skipMerge: true);
  });

  /// Decrypts [file] and merges it into the local DB (newer local edits win).
  /// If no passphrase is set yet, [passphrase] becomes the session passphrase.
  Future<ImportReport> openVault(
    File file,
    String passphrase, {
    bool remember = false,
  }) => _serial(() async {
    _checkPassphrase(passphrase);
    final env = VaultCodec.parse(await file.readAsBytes());
    final key = await _keyFor(env.header, passphrase);
    final plain = await VaultCodec.decrypt(env, key);
    final report = await backup.importJson(utf8.decode(plain));
    if (!isUnlocked) {
      await _startSession(passphrase, remember: remember);
      _createdAt = env.header.createdAt;
    }
    // Just merged our own file: the next auto-save needn't re-read it.
    if (file.absolute.path == (await vaultFile).absolute.path) {
      _knownModified = await _modified();
    }
    return report;
  });

  /// Re-encrypts the vault under [next] with a fresh salt.
  Future<File> changePassphrase(String current, String next) =>
      _serial(() async {
        if (!isUnlocked || current != _passphrase) {
          throw const VaultAuthException();
        }
        _checkPassphrase(next);
        final remembered = await _keychainHas();
        await _merge(
          current,
        ); // keep anything written elsewhere under the old key
        await _startSession(next, remember: remembered);
        return _write(skipMerge: true);
      });

  /// Writes the vault now with the session passphrase (Settings → Save now).
  Future<File> saveNow() => _serial(() {
    if (!isUnlocked) throw StateError('Vault is locked.');
    return _write();
  });

  /// Unlocks with the passphrase remembered in the Keychain: merges the
  /// existing vault (or creates one). False if nothing is remembered. Throws
  /// [VaultAuthException] if the remembered passphrase no longer opens the
  /// file; the vault then stays locked.
  Future<bool> unlockFromKeychain() async {
    if (isUnlocked) return true;
    final saved = await _keychain.read(key: _keychainKey);
    if (saved == null) return false;
    final file = await vaultFile;
    if (await file.exists()) {
      await openVault(file, saved);
    } else {
      await saveVault(saved);
    }
    return true;
  }

  /// Whether a passphrase is remembered in the Keychain.
  Future<bool> get remembered => _keychainHas();

  /// Ends the session: stops auto-save and drops the key from memory.
  /// [forget] also removes the passphrase from the Keychain.
  Future<void> lock({bool forget = false}) => _serial(() async {
    _stopAutoSave();
    _passphrase = _salt = _key = null;
    unlocked.value = false;
    if (forget) await _keychain.delete(key: _keychainKey);
  });

  void dispose() {
    _stopAutoSave();
    lastSavedAt.dispose();
    unlocked.dispose();
    lastError.dispose();
  }

  // ---------------------------------------------------------------------------

  void _checkPassphrase(String p) {
    if (p.isEmpty) throw ArgumentError('Passphrase must not be empty.');
  }

  Future<void> _startSession(
    String passphrase, {
    required bool remember,
  }) async {
    final salt = _randomBytes(VaultCodec.saltLength);
    _key = await VaultCodec.deriveKeyInBackground(passphrase, salt, iterations);
    _salt = salt;
    _passphrase = passphrase;
    unlocked.value = true;
    if (remember) {
      await _keychain.write(key: _keychainKey, value: passphrase);
    }
    _startAutoSave();
  }

  void _startAutoSave() {
    if (_subs.isNotEmpty) return;
    void schedule() {
      _debounce?.cancel();
      _debounce = Timer(autoSaveDelay, () {
        _serial(() async {
          if (!isUnlocked) return;
          try {
            await _write();
          } catch (e) {
            lastError.value = e;
          }
        });
      });
    }

    _subs.add(store.changes.listen((_) => schedule()));
  }

  void _stopAutoSave() {
    _debounce?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  /// Merge-then-write, atomically. Caller holds the queue.
  Future<File> _write({bool skipMerge = false}) async {
    if (!skipMerge) await _merge(_passphrase!);
    final file = await vaultFile;
    final now = DateTime.now().toUtc();
    _createdAt ??= now;
    final bytes = await VaultCodec.encrypt(
      plaintext: utf8.encode(await backup.buildJson()),
      key: _key!,
      header: VaultHeader(
        iterations: iterations,
        salt: _salt!,
        nonce: _randomBytes(VaultCodec.nonceLength),
        createdAt: _createdAt!,
        updatedAt: now,
        deviceId: _deviceId(),
      ),
    );
    await writeAtomically(file, bytes);
    _knownModified = await _modified();
    lastSavedAt.value = now;
    lastError.value = null;
    return file;
  }

  /// Merges the on-disk vault if it changed since we last saw it. Throws (and
  /// so blocks the write) if it can't be decrypted — never overwrite data we
  /// couldn't read.
  Future<void> _merge(String passphrase) async {
    final modified = await _modified();
    if (modified == null || modified == _knownModified) return;
    final env = VaultCodec.parse(await (await vaultFile).readAsBytes());
    final plain = await VaultCodec.decrypt(
      env,
      await _keyFor(env.header, passphrase),
    );
    await backup.importJson(utf8.decode(plain));
    _createdAt ??= env.header.createdAt;
    _knownModified = modified;
  }

  Future<Uint8List> _keyFor(VaultHeader h, String passphrase) async {
    if (passphrase == _passphrase &&
        h.iterations == iterations &&
        listEquals(h.salt, _salt)) {
      return _key!;
    }
    return VaultCodec.deriveKeyInBackground(passphrase, h.salt, h.iterations);
  }

  Future<DateTime?> _modified() async {
    final f = await vaultFile;
    return await f.exists() ? f.lastModified() : null;
  }

  Future<bool> _keychainHas() async =>
      await _keychain.read(key: _keychainKey) != null;

  String _deviceId() {
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  /// One vault operation at a time, in call order. A failed one doesn't
  /// block the next.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// Writes [bytes] to `<target>.tmp`, then renames it over [target]. A failure
/// at any point leaves the previous [target] untouched.
@visibleForTesting
Future<void> writeAtomically(File target, List<int> bytes) async {
  final tmp = File('${target.path}.tmp');
  try {
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
  } catch (_) {
    try {
      await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}
