import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInException, GoogleSignInExceptionCode;
import 'package:http/http.dart' show ClientException;
import 'package:life_manager/services/auth_service.dart';
import 'package:life_manager/services/session_controller.dart';
import 'package:life_manager/services/sync_service.dart' show describeSyncError;
import 'package:life_manager/util/net.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A session shaped like the real thing — only the fields the controller and
/// the Settings screen touch need to be meaningful.
Session _session({String email = 'someone@example.com'}) => Session.fromJson({
      'access_token': 'access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': '00000000-0000-4000-8000-000000000000',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'aud': 'authenticated',
        'email': email,
        'created_at': '2026-01-01T00:00:00Z',
      },
    })!;

void main() {
  group('SessionController', () {
    late StreamController<AuthState> events;

    setUp(() => events = StreamController<AuthState>.broadcast());
    tearDown(() => events.close());

    SessionController controller({Session? initial}) => SessionController(
          events: events.stream,
          initialSession: initial,
        );

    test('a persisted session is signed in from the first frame', () {
      // No await: an offline cold start must not show a spinner or a flash of
      // the sign-in screen while the network is consulted.
      expect(controller(initial: _session()).state.phase, AuthPhase.signedIn);
    });

    test('no persisted session means signed out', () {
      expect(controller().state.phase, AuthPhase.signedOut);
    });

    test('a failed token refresh does not sign the user out', () async {
      final c = controller(initial: _session());

      // What gotrue emits for every offline refresh: a stream *error*, with
      // the session left deliberately intact.
      events.addError(AuthRetryableFetchException(message: 'no connection'));
      await pumpEventQueue();

      expect(c.state.phase, AuthPhase.signedIn);
      expect(c.state.session, isNotNull);
    });

    test('repeated refresh failures still do not sign the user out', () async {
      final c = controller(initial: _session());

      // The auto-refresh ticker regenerates this every 10s for as long as the
      // connection is down — a long flight is thousands of these.
      for (var i = 0; i < 50; i++) {
        events.addError(AuthRetryableFetchException(message: 'no connection'));
      }
      await pumpEventQueue();

      expect(c.state.phase, AuthPhase.signedIn);
    });

    test('an explicit signedOut event does sign the user out', () async {
      final c = controller(initial: _session());

      events.add(const AuthState(AuthChangeEvent.signedOut, null));
      await pumpEventQueue();

      expect(c.state.phase, AuthPhase.signedOut);
      expect(c.state.session, isNull);
    });

    test('a revoked refresh token signs the user out', () async {
      final c = controller(initial: _session());

      events.add(const AuthState(
        AuthChangeEvent.signedOut,
        null,
        signOutReason: SignOutReason.sessionExpired,
      ));
      await pumpEventQueue();

      expect(c.state.phase, AuthPhase.signedOut);
    });

    test('signing in from the sign-in screen carries the session through',
        () async {
      final c = controller();

      events.add(AuthState(
        AuthChangeEvent.signedIn,
        _session(email: 'new@example.com'),
      ));
      await pumpEventQueue();

      expect(c.state.phase, AuthPhase.signedIn);
      expect(c.state.session?.user.email, 'new@example.com');
    });

    test('a session-less event that is not signedOut is ignored', () async {
      final c = controller(initial: _session());

      // `initialSession` can arrive with a null session after we have already
      // seeded from `currentSession`; it must not undo that.
      events.add(const AuthState(AuthChangeEvent.initialSession, null));
      await pumpEventQueue();

      expect(c.state.phase, AuthPhase.signedIn);
    });

    test('unconfigured builds report unknown rather than signed out', () {
      // Local-only installs have no account to be signed out of — reporting
      // signedOut here would put a sign-in screen in front of a build that has
      // no way to satisfy it.
      expect(SessionController.unconfigured().state.phase, AuthPhase.unknown);
    });
  });

  // These read the summary with `startsWith`: debug builds (which tests are)
  // append the raw exception, and that suffix is not what's under test.
  group('describeSyncError', () {
    test('an unreachable server is not reported as an expired session', () {
      // `AuthRetryableFetchException` extends `AuthException`, so arm order in
      // the switch decides this. "Sign in again" is both wrong and impossible
      // to act on with no network.
      expect(
        describeSyncError(AuthRetryableFetchException(message: 'offline')),
        startsWith('No connection'),
      );
    });

    test('a genuinely rejected session still says so', () {
      expect(
        describeSyncError(const AuthException('invalid token')),
        startsWith('Session expired — sign in again'),
      );
    });
  });

  group('describeAuthError', () {
    test('an offline sign-in attempt says so, and that data is safe', () {
      final message = AuthService.describeAuthError(
        AuthRetryableFetchException(message: 'offline'),
      );
      expect(message, contains('No connection'));
      expect(message, contains('safe on this device'));
    });

    test('a cancelled sign-in is still reported as cancelled', () {
      expect(
        AuthService.describeAuthError(const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        )),
        startsWith('Sign-in cancelled'),
      );
    });
  });

  group('isOfflineError', () {
    test('transport failures count as offline', () {
      expect(isOfflineError(const SocketException('failed')), isTrue);
      expect(isOfflineError(ClientException('failed')), isTrue);
      expect(isOfflineError(TimeoutException('failed')), isTrue);
      expect(
        isOfflineError(AuthRetryableFetchException(message: 'failed')),
        isTrue,
      );
    });

    test('a server that answered and said no is not offline', () {
      // These must surface as real errors and must not park the engine in the
      // offline retry loop, which would hide them behind "will sync later".
      expect(
        isOfflineError(const PostgrestException(message: 'denied', code: '42501')),
        isFalse,
      );
      expect(isOfflineError(const AuthException('bad token')), isFalse);
      expect(isOfflineError(StateError('bug')), isFalse);
    });
  });
}
