import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keychain / Keystore-backed session storage for Supabase Auth.
///
/// `supabase_flutter` defaults to [SharedPreferencesLocalStorage], which writes
/// the persisted session — including the long-lived **refresh token** — as
/// plaintext into `NSUserDefaults` (iOS) or an XML file (Android). Both sit in
/// the app sandbox unencrypted and both are swept up by platform backups.
///
/// These wrappers move that material into the iOS Keychain / Android Keystore
/// instead, and migrate anything already written in the clear on first run.
///
/// On Apple platforms the items are marked `first_unlock_this_device` and
/// non-synchronizable, so they never leave the device via iCloud Keychain and
/// don't restore onto a different one.
const _appleOptions = IOSOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
  synchronizable: false,
);

const _macOptions = MacOsOptions(
  accessibility: KeychainAccessibility.first_unlock_this_device,
  synchronizable: false,
);

/// Shared handle — `flutter_secure_storage` defaults to AES-GCM data
/// encryption under an RSA-OAEP Keystore-wrapped key on Android, which is
/// already what we want, so only the Apple options need overriding.
///
/// Pinned to the 10.x line deliberately: 11.0.0 requires `compileSdk = 37`,
/// which this project's Android Gradle Plugin doesn't support yet. The Android
/// cipher defaults are identical between the two.
const _secure = FlutterSecureStorage(
  iOptions: _appleOptions,
  mOptions: _macOptions,
);

/// Drop-in replacement for [SharedPreferencesLocalStorage].
class SecureLocalStorage extends LocalStorage {
  SecureLocalStorage({required this.persistSessionKey});

  /// Same key `supabase_flutter` would have used, so the migration below can
  /// find a session written by an earlier build.
  final String persistSessionKey;

  @override
  Future<void> initialize() async {
    await _migrateFromSharedPreferences();
  }

  /// One-time move of a plaintext session into the Keychain/Keystore. Runs on
  /// every launch but does nothing once the old key is gone.
  Future<void> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null) return;
      // Only overwrite if we don't already hold a (newer) secure copy.
      if (await _secure.read(key: persistSessionKey) == null) {
        await _secure.write(key: persistSessionKey, value: legacy);
      }
      await prefs.remove(persistSessionKey);
    } catch (_) {
      // A failed migration must never block startup — worst case the user
      // signs in again and the session is written securely from then on.
    }
  }

  @override
  Future<bool> hasAccessToken() =>
      _secure.containsKey(key: persistSessionKey);

  @override
  Future<String?> accessToken() => _secure.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _secure.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _secure.write(key: persistSessionKey, value: persistSessionString);
}

/// Secure equivalent of `SharedPreferencesGotrueAsyncStorage` — holds the PKCE
/// code verifier, which is short-lived but still a credential in flight.
class SecureGotrueAsyncStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) => _secure.read(key: key);

  @override
  Future<void> setItem({required String key, required String value}) =>
      _secure.write(key: key, value: value);

  @override
  Future<void> removeItem({required String key}) => _secure.delete(key: key);
}

/// The key `supabase_flutter` derives internally — mirrored here so a session
/// persisted by an older build is found by [SecureLocalStorage.initialize].
String persistSessionKeyFor(String supabaseUrl) =>
    'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';
