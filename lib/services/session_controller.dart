import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'auth_service.dart';

/// Where this device stands with Supabase Auth.
enum AuthPhase {
  /// Nothing decided yet — Supabase isn't configured, or the first event
  /// hasn't landed.
  unknown,

  /// A session exists on this device. It may be *expired and unrefreshable
  /// right now* (no connection) and that still counts: the refresh token is in
  /// the Keychain and gotrue retries on its own every 10s while foregrounded.
  signedIn,

  /// The server told us the session is gone (refresh token revoked/invalid) or
  /// the user signed out here. This is the only route back to the sign-in
  /// screen.
  signedOut,
}

@immutable
class SessionState {
  const SessionState({required this.phase, this.session});

  final AuthPhase phase;

  /// The last session we held. Kept even once expired, so Settings can still
  /// show who's signed in while offline.
  final Session? session;

  bool get isSignedIn => phase == AuthPhase.signedIn;
}

/// Offline-tolerant view of [AuthService.authStateChanges].
///
/// The raw gotrue stream carries two very different kinds of "bad news" and
/// conflating them is what used to bounce people to the sign-in screen on a
/// train:
///
///  * **Events** — `signedOut` means the server rejected the refresh token, or
///    the user signed out. That's real; act on it.
///  * **Stream errors** — gotrue's `_doRefresh` calls `notifyException` (which
///    does `controller.addError`) for any *retryable* failure, i.e. every
///    offline token refresh. It deliberately keeps `_currentSession` intact
///    when it does this, because nothing is actually wrong with the session.
///
/// Watching the stream through a plain `StreamProvider` collapses the second
/// case into `AsyncError`, and the auto-refresh ticker regenerates that error
/// every 10 seconds for as long as you're offline. So this controller drops
/// errors on the floor for the purpose of *phase*, and only ever moves to
/// [AuthPhase.signedOut] on an explicit `signedOut` event.
class SessionController extends StateNotifier<SessionState> {
  /// [initialSession] is what this device already holds, read synchronously so
  /// the very first frame is correct.
  ///
  /// `Supabase.initialize` awaits `SupabaseAuth.initialize`, which calls
  /// `setInitialSession` with whatever was persisted — so by the time `main()`
  /// reaches `runApp`, `currentSession` is populated (possibly with an expired
  /// session) whenever this device has ever signed in. Seeding from it means
  /// no spinner and no flash of the sign-in screen on a cold offline start.
  SessionController({
    required Stream<AuthState> events,
    required Session? initialSession,
  }) : super(SessionState(
          phase:
              initialSession == null ? AuthPhase.signedOut : AuthPhase.signedIn,
          session: initialSession,
        )) {
    _sub = events.listen(
      _onEvent,
      // Must be present even though it does nothing: an unhandled error on a
      // stream subscription escapes to the zone, and offline that fires on
      // every refresh tick.
      onError: (_, _) {},
    );
  }

  /// Local-only builds: no Supabase, so there is nothing to be signed in or
  /// out of. [AuthGate] short-circuits before reaching this, but the provider
  /// still has to produce something.
  SessionController.unconfigured()
      : _sub = null,
        super(const SessionState(phase: AuthPhase.unknown));

  /// Wires up against the live Supabase client.
  factory SessionController.from(AuthService auth) => SupabaseConfig.isConfigured
      ? SessionController(
          events: auth.authStateChanges,
          initialSession: auth.currentSession,
        )
      : SessionController.unconfigured();

  StreamSubscription<AuthState>? _sub;

  void _onEvent(AuthState event) {
    final session = event.session;
    if (session != null) {
      state = SessionState(phase: AuthPhase.signedIn, session: session);
      return;
    }
    if (event.event == AuthChangeEvent.signedOut) {
      state = const SessionState(phase: AuthPhase.signedOut);
    }
    // Any other session-less event (e.g. `initialSession` on a fresh install
    // where `setInitialSession` was never reached) leaves the phase alone —
    // the constructor's seed already decided it.
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
