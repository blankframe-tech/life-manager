package tech.blankframe.life_manager

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by `local_auth`:
// the biometric prompt is a Fragment, so it needs a FragmentActivity host.
// Without this the app-lock prompt throws `no_fragment_activity` at runtime.
class MainActivity : FlutterFragmentActivity()
