import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/seed_loader.dart';
import 'models/history_event.dart';
import 'models/item.dart';
import 'providers/providers.dart';
import 'services/budget_reset_service.dart';
import 'services/secure_session_storage.dart';
import 'theme/app_theme.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Local DB — the source of truth the UI renders from.
  final dir = await getApplicationDocumentsDirectory();
  final isar =
      await Isar.open([ItemSchema, HistoryEventSchema], directory: dir.path);

  // One-time bootstrap from the bundled seed (if present). When Supabase is
  // configured this instead runs from AuthGate once a session exists — an
  // unauthenticated "is the cloud empty" check looks empty even when it
  // isn't under owner-only RLS, so seeding must wait for real auth.
  if (!SupabaseConfig.isConfigured) {
    await SeedLoader.seedIfNeeded(isar);
  }

  final prefs = await SharedPreferences.getInstance();

  // Un-tick any checked-off Needs items on the first launch of a new month.
  await resetNeedsIfNewMonth(isar, prefs);

  runApp(
    ProviderScope(
      overrides: [
        isarProvider.overrideWithValue(isar),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const LifeManagerApp(),
    ),
  );
}

class LifeManagerApp extends ConsumerWidget {
  const LifeManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Life Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(brightness: Brightness.dark),
      themeMode: themeMode,
      home: const AppLockGate(child: AuthGate()),
    );
  }
}
