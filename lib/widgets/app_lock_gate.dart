import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// Wraps the app in a biometric lock when the user has enabled it in Settings.
///
/// Locks on launch and again whenever the app leaves the foreground, so the
/// data isn't sitting visible in the app switcher's snapshot or on a handed-over
/// phone. When the lock is disabled (the default) this is a pass-through.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  /// Start locked: `build` unlocks immediately if the setting is off, so a
  /// launch with the lock on can never flash the contents first.
  bool _locked = true;
  bool _prompting = false;

  /// Whether this lock episode has already prompted automatically. Without it,
  /// a cancelled prompt would leave `_locked` true, trigger a rebuild, and
  /// immediately re-prompt — an inescapable loop. Cancelling should leave the
  /// user on the lock screen with a button they can press when ready.
  bool _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(appLockEnabledProvider)) return;
    // `paused` covers backgrounding; `hidden` fires first on newer engines.
    // Re-lock on the way out rather than on the way back in, so the snapshot
    // the OS takes for the app switcher shows the lock screen, not the data.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!_prompting && !_locked) {
        setState(() {
          _locked = true;
          _autoPrompted = false;
        });
      }
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    setState(() => _prompting = true);
    final ok = await ref.read(appLockServiceProvider).authenticate();
    if (!mounted) return;
    setState(() {
      _prompting = false;
      if (ok) _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockEnabledProvider);
    if (!enabled) {
      // Setting turned off (now or at launch) — nothing to guard.
      if (_locked) _locked = false;
      return widget.child;
    }

    // The lock is on — but is the device still able to satisfy it? Biometrics
    // can be un-enrolled and a passcode removed after the fact, and a lock
    // whose prompt can never succeed is a permanent lockout with the data
    // stranded on-device. Failing open is safe here: removing a screen lock
    // requires entering the existing one, so this isn't an attacker's path in.
    // A failed capability check counts as "can't authenticate" for the same
    // reason — never hold the user behind a prompt we can't reason about.
    final availability = ref.watch(appLockAvailableProvider);
    final available =
        availability.hasError ? false : availability.valueOrNull;
    if (available == false) {
      // Turn the setting off so Settings shows the truth rather than a switch
      // that claims to be protecting something.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(appLockEnabledProvider.notifier).set(false);
      });
      return widget.child;
    }
    // Still resolving — hold on the lock screen rather than flashing content.
    if (available == null) return _lockScreen(context, canPrompt: false);

    if (!_locked) return widget.child;

    // Prompt once, as soon as the lock screen is on-screen, without blocking
    // build. After that it's on the Unlock button — see [_autoPrompted].
    if (!_prompting && !_autoPrompted) {
      _autoPrompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _locked && !_prompting) _unlock();
      });
    }

    return _lockScreen(context, canPrompt: true);
  }

  Widget _lockScreen(BuildContext context, {required bool canPrompt}) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.lock_fill, size: 56),
                const SizedBox(height: 20),
                Text('Locked',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Unlock with biometrics or your device passcode.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: (_prompting || !canPrompt) ? null : _unlock,
                  icon: const Icon(CupertinoIcons.lock_open),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
