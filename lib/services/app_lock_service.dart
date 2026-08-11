import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kAppLockEnabledKey = 'app_lock_enabled';

/// Biometric / device-passcode gate in front of the app.
///
/// This exists because the local Isar DB is **not** encrypted at rest — Isar 3
/// dropped the encryption support Isar 2 had, so there is no `encryptionKey` to
/// pass and no way to protect the file itself from Dart. Device-level disk
/// encryption is the only thing standing between a lost-but-unlocked phone and
/// every figure in the app. An app lock doesn't fix encryption at rest, but it
/// does close the realistic threat: someone picking up an unlocked handset.
///
/// Off by default — turning it on is a deliberate choice in Settings, and
/// [canLock] gates the toggle so a device with no biometrics and no passcode
/// can never enable it and strand the user.
class AppLockService {
  AppLockService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// True when the device can actually authenticate the user — biometrics
  /// enrolled, or at minimum a passcode/PIN set.
  Future<bool> canLock() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts for biometrics (falling back to the device passcode). Returns
  /// false on cancel, lockout, or any platform error — callers must treat
  /// false as "stay locked".
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Life Manager',
        // Allow the device passcode as a fallback: biometric-only would strand
        // the user behind a failed fingerprint with no way through.
        biometricOnly: false,
        // The OS backgrounds the app to show the prompt on some devices;
        // without this the attempt fails instead of resuming.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// Persisted on/off switch for the lock. Kept in SharedPreferences alongside
/// the other UI preferences — it's a setting, not a secret.
class AppLockNotifier extends StateNotifier<bool> {
  AppLockNotifier(this._prefs)
      : super(_prefs.getBool(_kAppLockEnabledKey) ?? false);

  final SharedPreferences _prefs;

  void set(bool enabled) {
    state = enabled;
    _prefs.setBool(_kAppLockEnabledKey, enabled);
  }
}
