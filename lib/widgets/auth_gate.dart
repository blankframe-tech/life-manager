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
///
/// "Signed in" here means *this device holds a session*, not *the server just
/// confirmed one*. Connectivity is not an authentication question: with the
/// refresh token in the Keychain and every item in Isar, there is nothing an
/// unreachable auth server can tell us that justifies locking someone out of
/// their own data. [SessionController] keeps the two apart; the only route to
/// [SignInScreen] is a real `signedOut` event.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!SupabaseConfig.isConfigured) return const RootScaffold();

    switch (ref.watch(sessionProvider).phase) {
      case AuthPhase.signedOut:
        return const SignInScreen();
      case AuthPhase.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthPhase.signedIn:
        // Deferred from main() — under owner-only RLS, an unauthenticated
        // "is the cloud empty" check looks empty even when it isn't, so
        // seeding must wait until a real session exists. Idempotent (guarded
        // by a marker file), so calling it on every rebuild is harmless, and
        // it no-ops without writing the marker when the cloud is unreachable,
        // so an offline launch simply defers the decision.
        unawaited(SeedLoader.seedIfNeeded(ref.read(isarProvider)));
        return const RootScaffold();
    }
  }
}
