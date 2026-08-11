import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Thin wrapper over Google Sign-In + Supabase Auth's ID-token exchange.
/// Only ever invoked when [SupabaseConfig.isConfigured] — the app has no
/// concept of "signed out but local" beyond that.
class AuthService {
  AuthService() {
    if (GoogleAuthConfig.isConfigured) {
      _ready = GoogleSignIn.instance.initialize(
        serverClientId: GoogleAuthConfig.serverClientId,
        nonce: _hashedNonce,
      );
    }
  }

  /// Resolves once `GoogleSignIn.instance` has been initialized — every
  /// Google Sign-In call must wait on this first.
  Future<void>? _ready;

  /// The nonce Supabase compares against, once hashed — see [_hashedNonce].
  ///
  /// `google_sign_in` 7.x takes the nonce on `initialize()` — which must be
  /// called exactly once per process — rather than per `authenticate()` call,
  /// so this is scoped to the app run instead of the individual attempt. That
  /// still delivers the property that matters: the claim is unpredictable and
  /// tied to *this* launch, so an ID token captured in any other context won't
  /// satisfy the check.
  final String _rawNonce = _generateNonce();

  /// What actually gets handed to Google.
  ///
  /// Supabase's id_token grant always hashes the nonce *we* give it
  /// (SHA-256, lowercase hex) and compares that against the token's `nonce`
  /// claim — there's no raw-value comparison. Google, in turn, embeds
  /// whatever nonce it's given verbatim, with no hashing of its own. So for
  /// the two sides to agree, Google has to receive the pre-hashed value while
  /// Supabase gets the raw one; passing the same string to both (as this used
  /// to) makes the claim equal the raw nonce, which then fails Supabase's
  /// hash comparison every time — `AuthApiException: Nonces mismatch`.
  late final String _hashedNonce =
      sha256.convert(utf8.encode(_rawNonce)).toString();

  SupabaseClient get _db => Supabase.instance.client;

  Stream<AuthState> get authStateChanges => _db.auth.onAuthStateChange;

  Session? get currentSession => _db.auth.currentSession;

  /// Fresh 256 bits of CSPRNG entropy, base64url-encoded. Called once per
  /// [AuthService] — see [_rawNonce] for why the scope is the app run.
  static String _generateNonce() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Signs in with Google and exchanges the resulting ID token for a Supabase
  /// session.
  ///
  /// [_rawNonce] binds the ID token to this app run, so a token captured
  /// elsewhere can't be replayed against our project. Google embedded
  /// [_hashedNonce] verbatim in the `nonce` claim (see its doc comment for
  /// why), so the raw value is what goes to Supabase here — it hashes this
  /// itself and compares against the claim.
  ///
  /// Supplying it is what lets "Skip nonce checks" be turned **off** in the
  /// Supabase dashboard — see HANDOFF.md.
  Future<void> signInWithGoogle() async {
    await _ready;
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google sign-in did not return an ID token.');
    }
    await _db.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      nonce: _rawNonce,
    );
  }

  /// Screen-safe rendering of a sign-in failure. `AuthException` and the
  /// plugin's `GoogleSignInException` carry provider detail, request context
  /// and occasionally token fragments, so only a summary is surfaced; debug
  /// builds keep the original for diagnosis.
  static String describeAuthError(Object error) {
    final summary = switch (error) {
      GoogleSignInException(:final code) =>
        code == GoogleSignInExceptionCode.canceled
            ? 'Sign-in cancelled'
            : 'Google sign-in failed',
      AuthException() => 'Could not sign in — please try again',
      StateError() => 'Google did not return an ID token',
      _ => 'Sign-in failed',
    };
    return kDebugMode ? '$summary (debug: $error)' : summary;
  }

  Future<void> signOut() async {
    await _db.auth.signOut();
    await GoogleSignIn.instance.signOut();
  }
}
