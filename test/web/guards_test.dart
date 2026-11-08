import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/web/guards.dart';

void main() {
  test('throttle backs off exponentially and resets on success', () {
    var now = DateTime(2026);
    final t = PassphraseThrottle(clock: () => now);
    expect(t.wait, Duration.zero);
    t.fail();
    expect(t.wait, const Duration(seconds: 1));
    t.fail();
    t.fail();
    expect(t.wait, const Duration(seconds: 4));
    now = now.add(const Duration(seconds: 4));
    expect(t.wait, Duration.zero);
    for (var i = 0; i < 20; i++) {
      t.fail();
    }
    expect(t.wait, PassphraseThrottle.maxDelay);
    t.succeed();
    expect(t.wait, Duration.zero);
    expect(t.failures, 0);
  });

  test('auto-lock: idle and hidden timeouts', () {
    var now = DateTime(2026);
    final p = AutoLockPolicy(clock: () => now);
    now = now.add(const Duration(minutes: 9));
    expect(p.due(), isNull);
    p.activity();
    now = now.add(const Duration(minutes: 9));
    expect(p.due(), isNull);
    now = now.add(const Duration(minutes: 1));
    expect(p.due(), LockReason.idle);

    p.activity();
    p.visibilityChanged(visible: false);
    now = now.add(const Duration(minutes: 4));
    expect(p.due(), isNull);
    p.visibilityChanged(visible: false); // repeated hidden keeps the start
    now = now.add(const Duration(minutes: 1));
    expect(p.due(), LockReason.hidden);
    p.visibilityChanged(visible: true);
    p.activity();
    expect(p.due(), isNull);
  });

  test('auto-lock: returning after a suspended hidden spell still locks', () {
    // Background tabs (Safari on iOS) may get no timer tick at all while
    // hidden, so the 'visible' event is the first chance to check.
    var now = DateTime(2026);
    final p = AutoLockPolicy(clock: () => now);
    expect(p.visibilityChanged(visible: false), isNull);
    now = now.add(const Duration(minutes: 7));
    expect(p.due(), LockReason.hidden);
    expect(p.visibilityChanged(visible: true), LockReason.hidden);
    expect(p.due(), isNull, reason: 'hidden timestamp cleared afterwards');
  });

  test('auto-lock: a short hidden spell does not lock on return', () {
    var now = DateTime(2026);
    final p = AutoLockPolicy(clock: () => now);
    p.visibilityChanged(visible: false);
    now = now.add(const Duration(minutes: 2));
    expect(p.visibilityChanged(visible: true), isNull);
  });
}
