import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/providers/providers.dart';
import 'package:life_manager/services/app_lock_service.dart';
import 'package:life_manager/widgets/app_lock_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the platform biometric prompt: [canLock] decides whether the
/// device is considered capable, [authenticate] decides whether the user passes.
class _FakeAppLock extends AppLockService {
  _FakeAppLock({this.available = true, this.passes = true});

  final bool available;
  final bool passes;
  int prompts = 0;

  @override
  Future<bool> canLock() async => available;

  @override
  Future<bool> authenticate() async {
    prompts++;
    return passes;
  }
}

const _guarded = Text('SECRET');

Future<_FakeAppLock> _pumpGate(
  WidgetTester tester, {
  required bool lockEnabled,
  bool available = true,
  bool passes = true,
}) async {
  SharedPreferences.setMockInitialValues({'app_lock_enabled': lockEnabled});
  final prefs = await SharedPreferences.getInstance();
  final lock = _FakeAppLock(available: available, passes: passes);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appLockServiceProvider.overrideWithValue(lock),
      ],
      child: const MaterialApp(home: AppLockGate(child: _guarded)),
    ),
  );
  await tester.pumpAndSettle();
  return lock;
}

void main() {
  testWidgets('passes through when the lock is off', (tester) async {
    final lock = await _pumpGate(tester, lockEnabled: false);

    expect(find.text('SECRET'), findsOneWidget);
    expect(lock.prompts, 0, reason: 'must not prompt when the lock is off');
  });

  testWidgets('hides content behind the lock screen when enabled',
      (tester) async {
    final lock = await _pumpGate(tester, lockEnabled: true, passes: false);

    expect(find.text('SECRET'), findsNothing);
    expect(find.text('Locked'), findsOneWidget);
    expect(lock.prompts, 1, reason: 'should prompt once on its own');
  });

  testWidgets('reveals content after a successful unlock', (tester) async {
    await _pumpGate(tester, lockEnabled: true);

    expect(find.text('SECRET'), findsOneWidget);
    expect(find.text('Locked'), findsNothing);
  });

  testWidgets('a cancelled prompt does not re-prompt in a loop',
      (tester) async {
    final lock = await _pumpGate(tester, lockEnabled: true, passes: false);

    // Extra frames stand in for the rebuilds that a re-prompt loop would cause.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(lock.prompts, 1, reason: 'auto-prompt must fire at most once');
    expect(find.text('SECRET'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget,
        reason: 'the user needs a way back in after cancelling');
  });

  testWidgets('tapping Unlock re-prompts', (tester) async {
    final lock = await _pumpGate(tester, lockEnabled: true, passes: false);
    expect(lock.prompts, 1);

    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();

    expect(lock.prompts, 2);
  });

  testWidgets('fails open when the device can no longer authenticate',
      (tester) async {
    // The setting is on, but biometrics/passcode were removed since — locking
    // here would strand the user with no way to ever satisfy the prompt.
    final lock =
        await _pumpGate(tester, lockEnabled: true, available: false);

    expect(find.text('SECRET'), findsOneWidget);
    expect(lock.prompts, 0);
  });

  testWidgets('and turns the stale setting off', (tester) async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appLockServiceProvider
              .overrideWithValue(_FakeAppLock(available: false)),
        ],
        child: const MaterialApp(home: AppLockGate(child: _guarded)),
      ),
    );
    await tester.pumpAndSettle();

    expect(prefs.getBool('app_lock_enabled'), false,
        reason: 'Settings should reflect that the lock is not in force');
  });
}
