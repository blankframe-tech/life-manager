import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Pure encode / decode of the `.lmvault` file. No I/O, no Isar.
///
/// Layout (see docs/VAULT_FORMAT.md for the full spec):
///
/// ```
/// "LMV1" | uint32 BE headerLength | header JSON (UTF-8) | AES-GCM ciphertext || 16-byte tag
/// ```
///
/// Everything before the ciphertext is the AES-GCM associated data, so a
/// changed header byte fails authentication just like a changed ciphertext
/// byte. Every primitive is in browser WebCrypto (PBKDF2-SHA256, AES-256-GCM).
class VaultCodec {
  static const magic = [0x4C, 0x4D, 0x56, 0x31]; // "LMV1"
  static const formatVersion = 1;
  static const kdfName = 'PBKDF2-HMAC-SHA256';
  static const cipherName = 'AES-256-GCM';
  static const defaultIterations = 600000;

  /// Lowest count a reader accepts. Only the test vectors go this low.
  static const minIterations = 1000;

  /// Upper bound so a hostile file can't hang the app in the KDF.
  static const maxIterations = 10000000;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const tagLength = 16;
  static const maxHeaderLength = 64 * 1024;

  static final _aes = AesGcm.with256bits();

  /// PBKDF2-HMAC-SHA256 → 32-byte AES key. The passphrase is Unicode NFC
  /// normalized, then UTF-8 encoded — `TextEncoder().encode(p.normalize('NFC'))`
  /// in JS — so an iPhone keyboard and a desktop browser that compose "é"
  /// differently still derive the same key.
  static Future<Uint8List> deriveKey(
      String passphrase, List<int> salt, int iterations) async {
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode(unorm.nfc(passphrase))),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  /// [deriveKey] on a background isolate (600k rounds take seconds). On the
  /// web `compute` runs inline, but there the KDF is async WebCrypto anyway.
  static Future<Uint8List> deriveKeyInBackground(
          String passphrase, List<int> salt, int iterations) =>
      compute(_deriveEntry, (passphrase, Uint8List.fromList(salt), iterations));

  static Future<Uint8List> _deriveEntry((String, Uint8List, int) a) =>
      deriveKey(a.$1, a.$2, a.$3);

  /// Builds a complete vault file. [header] carries the salt and nonce; the
  /// caller picks them (random in the app, fixed in the test vectors).
  static Future<Uint8List> encrypt({
    required List<int> plaintext,
    required List<int> key,
    required VaultHeader header,
  }) async {
    final aad = _headerBlock(header);
    final box = await _aes.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: header.nonce,
      aad: aad,
    );
    return Uint8List.fromList([...aad, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Parses the unauthenticated framing. Throws [VaultFormatException] on
  /// anything that isn't a readable vault. The header is only trustworthy
  /// after [decrypt] succeeds.
  static VaultEnvelope parse(List<int> bytes) {
    if (bytes.length < 8) {
      throw const VaultFormatException('File is too short to be a vault.');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != magic[i]) {
        throw const VaultFormatException("That isn't a Life Manager vault.");
      }
    }
    final len = ByteData.sublistView(Uint8List.fromList(bytes.sublist(4, 8)))
        .getUint32(0);
    if (len > maxHeaderLength || 8 + len + tagLength > bytes.length) {
      throw const VaultFormatException('Vault header is damaged.');
    }
    final headerEnd = 8 + len;
    final VaultHeader header;
    try {
      header = VaultHeader.fromJson(
          jsonDecode(utf8.decode(bytes.sublist(8, headerEnd)))
              as Map<String, dynamic>);
    } on VaultException {
      rethrow;
    } catch (_) {
      throw const VaultFormatException('Vault header is damaged.');
    }
    return VaultEnvelope(
      header: header,
      aad: Uint8List.fromList(bytes.sublist(0, headerEnd)),
      body: Uint8List.fromList(bytes.sublist(headerEnd)),
    );
  }

  /// Decrypts with an already-derived [key]. A wrong key and a tampered byte
  /// are indistinguishable by design: both throw [VaultAuthException].
  static Future<Uint8List> decrypt(VaultEnvelope env, List<int> key) async {
    final split = env.body.length - tagLength;
    try {
      final plain = await _aes.decrypt(
        SecretBox(
          env.body.sublist(0, split),
          nonce: env.header.nonce,
          mac: Mac(env.body.sublist(split)),
        ),
        secretKey: SecretKey(key),
        aad: env.aad,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const VaultAuthException();
    }
  }

  /// "LMV1" + uint32 BE length + header JSON — the exact AAD bytes.
  static Uint8List _headerBlock(VaultHeader header) {
    final json = utf8.encode(jsonEncode(header.toJson()));
    final len = ByteData(4)..setUint32(0, json.length);
    return Uint8List.fromList(
        [...magic, ...len.buffer.asUint8List(), ...json]);
  }
}

/// The plaintext JSON metadata between the magic and the ciphertext.
class VaultHeader {
  VaultHeader({
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    this.version = VaultCodec.formatVersion,
  });

  final int version;
  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;

  Map<String, dynamic> toJson() => {
        'version': version,
        'kdf': VaultCodec.kdfName,
        'iterations': iterations,
        'salt': base64.encode(salt),
        'cipher': VaultCodec.cipherName,
        'nonce': base64.encode(nonce),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
      };

  static VaultHeader fromJson(Map<String, dynamic> m) {
    final version = m['version'];
    if (version is! int || version < 1) {
      throw const VaultFormatException('Vault header is damaged.');
    }
    if (version > VaultCodec.formatVersion) {
      throw VaultFormatException(
          'This vault was written by a newer version of the app '
          '(format $version, this build reads ${VaultCodec.formatVersion}).');
    }
    if (m['kdf'] != VaultCodec.kdfName || m['cipher'] != VaultCodec.cipherName) {
      throw const VaultFormatException('Unsupported vault encryption.');
    }
    final iterations = m['iterations'];
    if (iterations is! int ||
        iterations < VaultCodec.minIterations ||
        iterations > VaultCodec.maxIterations) {
      throw const VaultFormatException('Unsupported vault key settings.');
    }
    final salt = base64.decode(m['salt'] as String);
    final nonce = base64.decode(m['nonce'] as String);
    if (salt.length != VaultCodec.saltLength ||
        nonce.length != VaultCodec.nonceLength) {
      throw const VaultFormatException('Vault header is damaged.');
    }
    return VaultHeader(
      version: version,
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      createdAt: DateTime.parse(m['createdAt'] as String),
      updatedAt: DateTime.parse(m['updatedAt'] as String),
      deviceId: m['deviceId'] as String,
    );
  }
}

/// A parsed but not yet authenticated vault.
class VaultEnvelope {
  const VaultEnvelope(
      {required this.header, required this.aad, required this.body});

  final VaultHeader header;

  /// Bytes 0 .. end of header JSON, fed to AES-GCM as associated data.
  final Uint8List aad;

  /// Ciphertext followed by the 16-byte GCM tag.
  final Uint8List body;
}

/// Base of every vault failure. Messages are safe to show the user.
sealed class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Not a vault, damaged framing, or a format/version this build can't read.
class VaultFormatException extends VaultException {
  const VaultFormatException(super.message);
}

/// Wrong passphrase, or the file was modified. AES-GCM can't tell them apart.
class VaultAuthException extends VaultException {
  const VaultAuthException()
      : super('Wrong passphrase, or the vault file was modified.');
}
