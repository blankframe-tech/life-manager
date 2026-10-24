import 'dart:math';

/// Exponential backoff after wrong passphrases on the web login screen.
///
/// Honest limits: this only slows someone typing guesses into *this* tab, and
/// it resets on reload. Anyone holding a copy of the `.lmvault` file can guess
/// offline as fast as their hardware allows. The real defence is the KDF cost
/// (PBKDF2-SHA256, 600,000 rounds per guess) plus a long passphrase.
class PassphraseThrottle {
  PassphraseThrottle({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;
  int _failures = 0;
  DateTime? _until;

  static const maxDelay = Duration(minutes: 5);

  int get failures => _failures;

  /// Time left before the next attempt is allowed (zero when allowed).
  Duration get wait {
    final until = _until;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  /// 1 s after the first failure, doubling each time, capped at [maxDelay].
  static Duration delayAfter(int failures) => failures <= 0
      ? Duration.zero
      : Duration(seconds: min(1 << min(failures - 1, 16), maxDelay.inSeconds));

  void fail() {
    _failures++;
    _until = _now().add(delayAfter(_failures));
  }

  void succeed() {
    _failures = 0;
    _until = null;
  }
}

/// Why the vault locked itself.
enum LockReason { manual, idle, hidden }

/// Decides when an unlocked web session should lock: after [idle] without
/// input, or after the tab has been hidden for [hidden]. Pure logic — the
/// shell feeds it input and visibility events and calls [due] on a timer.
class AutoLockPolicy {
  AutoLockPolicy({
    this.idle = const Duration(minutes: 10),
    this.hidden = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now {
    _lastActive = _now();
  }

  final Duration idle;
  final Duration hidden;
  final DateTime Function() _now;
  late DateTime _lastActive;
  DateTime? _hiddenSince;

  void activity() => _lastActive = _now();

  void visibilityChanged({required bool visible}) =>
      _hiddenSince = visible ? null : (_hiddenSince ?? _now());

  /// Non-null when the session should lock now. Background tabs throttle
  /// timers, so this compares timestamps rather than counting ticks.
  LockReason? due() {
    final now = _now();
    final since = _hiddenSince;
    if (since != null && now.difference(since) >= hidden) {
      return LockReason.hidden;
    }
    if (now.difference(_lastActive) >= idle) return LockReason.idle;
    return null;
  }
}
