import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' show ClientException;
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

/// Whether a failure means "the network isn't there" rather than "the server
/// answered and said no".
///
/// The distinction is the spine of the offline behaviour. An unreachable
/// server is a temporary state to retry out of quietly — it must never sign
/// anyone out, must not be shown as a sync *error*, and must not stop the
/// pending queue from being retried. A rejection (RLS, bad token, constraint
/// violation) is a real problem that has to surface.
///
/// `AuthRetryableFetchException` is gotrue's wrapper around the same transport
/// failures, raised when a token refresh can't reach the server; it arrives as
/// a stream error on `onAuthStateChange` rather than as an event.
bool isOfflineError(Object error) =>
    error is SocketException ||
    error is ClientException ||
    error is TimeoutException ||
    error is AuthRetryableFetchException;
