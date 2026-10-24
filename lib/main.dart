import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Platform startup. The web one never touches Isar, the Keychain or Supabase.
import 'boot/boot_native.dart' if (dart.library.js_interop) 'boot/boot_web.dart';
import 'providers/providers.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled fonts are SIL OFL — list them on Settings → About → Licences.
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in const [
      ('DM Sans', 'OFL-DMSans.txt'),
      ('Newsreader', 'OFL-Newsreader.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  await boot();
}

class LifeManagerApp extends ConsumerWidget {
  const LifeManagerApp({
    super.key,
    required this.home,
    this.builder,
    this.navigatorKey,
  });

  /// The first screen: the native gates, or the web shell.
  final Widget home;

  /// Wraps every route (the web build adds its lock / sync bar here).
  final TransitionBuilder? builder;

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Life Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(brightness: Brightness.dark),
      themeMode: themeMode,
      navigatorKey: navigatorKey,
      builder: builder,
      home: home,
    );
  }
}
