import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../web/web_app.dart';

/// Web startup. No Isar, Keychain, app lock, Supabase or open-in: the data
/// comes from the vault file the user picks, and lives only in memory.
Future<void> boot() async {
  // The shared_preferences web plugin writes to localStorage. Swap it for a
  // memory-only store before anything reads preferences, so settings like
  // the salary never land in the browser in plaintext.
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
  runApp(const WebApp());
}
