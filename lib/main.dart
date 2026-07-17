import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_community/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/seed_loader.dart';
import 'models/item.dart';
import 'providers/providers.dart';
import 'screens/root_scaffold.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Cloud (optional — the app is fully usable offline without keys).
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  // Local DB — the source of truth the UI renders from.
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open([ItemSchema], directory: dir.path);

  // One-time bootstrap from the bundled seed (if present).
  await SeedLoader.seedIfNeeded(isar);

  runApp(
    ProviderScope(
      overrides: [isarProvider.overrideWithValue(isar)],
      child: const LifeManagerApp(),
    ),
  );
}

class LifeManagerApp extends StatelessWidget {
  const LifeManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const RootScaffold(),
    );
  }
}
