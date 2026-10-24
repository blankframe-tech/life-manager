import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../data/seed_loader.dart';
import '../main.dart';
import '../providers/providers.dart';
import '../screens/onboarding_screen.dart';
import '../services/budget_reset_service.dart';
import '../services/local_db.dart';
import '../services/secure_session_storage.dart';
import '../store/isar_store.dart';
import '../vault/vault_open_in.dart';
import '../vault/vault_ui.dart';
import '../widgets/app_lock_gate.dart';
import '../widgets/auth_gate.dart';

/// iOS / Android startup: Supabase (if on), the Isar DB, then the app behind
/// the app lock, vault, onboarding and auth gates.
Future<void> boot() async {
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Cloud (optional — the app is fully usable offline without keys).
  if (SupabaseConfig.isConfigured) {
    // Keep the session (and its long-lived refresh token) in the Keychain /
    // Keystore rather than the plaintext SharedPreferences default.
    final authOptions = FlutterAuthClientOptions(
      localStorage: SecureLocalStorage(
        persistSessionKey: persistSessionKeyFor(SupabaseConfig.url),
      ),
      pkceAsyncStorage: SecureGotrueAsyncStorage(),
    );
    if (SupabaseConfig.isPublishableKey) {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.anonKey,
        authOptions: authOptions,
      );
    } else {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // ignore: deprecated_member_use — legacy anon JWT fallback.
        anonKey: SupabaseConfig.anonKey,
        authOptions: authOptions,
      );
    }
  }

  // Local DB — the source of truth the UI renders from. Lives in Application
  // Support; Documents is visible in Files and holds only the encrypted vault.
  final store = IsarStore(await openLocalDb());

  // One-time bootstrap from the bundled seed (if present). When Supabase is
  // configured this instead runs from AuthGate once a session exists — an
  // unauthenticated "is the cloud empty" check looks empty even when it
  // isn't under owner-only RLS, so seeding must wait for real auth.
  if (!SupabaseConfig.isConfigured) {
    await SeedLoader.seedIfNeeded(store);
  }

  final prefs = await SharedPreferences.getInstance();

  // Un-tick any checked-off Needs items on the first launch of a new month.
  await resetNeedsIfNewMonth(store, prefs);

  // .lmvault files that launched the app from Files / AirDrop.
  await VaultOpenIn.start();

  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const LifeManagerApp(
        home: AppLockGate(
          child: VaultGate(child: OnboardingGate(child: AuthGate())),
        ),
      ),
    ),
  );
}
