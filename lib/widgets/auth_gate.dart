import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/supabase_config.dart';
import '../data/seed_loader.dart';
import '../providers/providers.dart';
import '../screens/root_scaffold.dart';
import '../screens/sign_in_screen.dart';

/// Gates [RootScaffold] behind a signed-in session — but only when Supabase
/// is configured. Local-only installs (no `--dart-define` keys) skip this
/// entirely and go straight to the app, unchanged from before auth existed.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!SupabaseConfig.isConfigured) return const RootScaffold();

    final authState = ref.watch(authStateProvider);
    return authState.when(
      data: (state) {
        if (state.session == null) return const SignInScreen();
        // Deferred from main() — under owner-only RLS, an unauthenticated
        // "is the cloud empty" check looks empty even when it isn't, so
        // seeding must wait until a real session exists. Idempotent (guarded
        // by a marker file), so calling it on every rebuild is harmless.
        unawaited(SeedLoader.seedIfNeeded(ref.read(isarProvider)));
        return const RootScaffold();
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      // Treat a broken auth stream as "not signed in" rather than a dead end.
      error: (_, _) => const SignInScreen(),
    );
  }
}
