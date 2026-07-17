/// Supabase connection settings.
///
/// The values are read at build time from `--dart-define` so real keys never
/// need to live in source control. Provide them like:
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
///
/// If neither is supplied the app runs fully offline (local-only) — every
/// screen still works; changes just aren't pushed to the cloud until keys are
/// configured. The anon key is a public client key (safe to ship), but keeping
/// it out of git keeps the repo clean.
class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// True only when both values were provided at build time.
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
