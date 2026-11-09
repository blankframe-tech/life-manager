import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/app_modules.dart';
import 'package:life_manager/boot/boot_native.dart';
import 'package:life_manager/providers/providers.dart';
import 'package:life_manager/services/app_lock_service.dart';
import 'package:life_manager/services/backup_service.dart';
import 'package:life_manager/store/memory_store.dart';
import 'package:life_manager/vault/vault_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for Face ID: [passes] decides every prompt from now on.
class _FakeAppLock extends AppLockService {
  bool passes = true;
  int prompts = 0;

  @override
  Future<bool> canLock() async => true;

  @override
  Future<bool> authenticate() async {
    prompts++;
    return passes;
  }
}

class _CountingBackup extends BackupService {
  _CountingBackup(super.store);
  int exports = 0;

  @override
  Future<File> writeExportFile() async {
    exports++;
    throw const FileSystemException('test: no export');
  }
}

/// The real native tree (lock, vault, onboarding, auth gates) over memory,
/// with the lock on, unlocked and Settings opened from Home's gear.
Future<({_FakeAppLock lock, SharedPreferences prefs, _CountingBackup backup})>
_openSettings(WidgetTester tester) async {
  // Tall enough that all of Settings is built without scrolling.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    'app_lock_enabled': true,
    'onboarding_done_v2': true,
    'module_intros_seen': [for (final m in kAppConfig.modules) m.id],
  });
  final prefs = await SharedPreferences.getInstance();
  final store = MemoryStore();
  final lock = _FakeAppLock();
  final backup = _CountingBackup(store);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appLockServiceProvider.overrideWithValue(lock),
        backupServiceProvider.overrideWithValue(backup),
        vaultServiceProvider.overrideWithValue(
          VaultService(
            store,
            prefs: prefs,
            backup: backup,
            documentsDir: () async => Directory.systemTemp.createTempSync(),
          ),
        ),
      ],
      child: nativeApp(),
    ),
  );
  await _settle(tester);
  expect(lock.prompts, 1, reason: 'launch with the lock on prompts once');
  expect(find.text('Locked'), findsNothing);

  await tester.tap(find.byTooltip('Settings'));
  await _settle(tester);
  expect(find.text('Require unlock'), findsOneWidget);
  return (lock: lock, prefs: prefs, backup: backup);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _background(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
}

Future<void> _foreground(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pump();
  }
  await _settle(tester);
}

void main() {
  testWidgets('re-lock covers a pushed route such as Settings', (tester) async {
    final t = await _openSettings(tester);

    t.lock.passes = false; // whoever picks up the phone cancels Face ID
    await _background(tester);
    await _foreground(tester);

    expect(t.lock.prompts, 2, reason: 'coming back prompts again');
    expect(find.text('Locked'), findsOneWidget);
    expect(find.text('Require unlock'), findsNothing);
    final hidden = find.text('Require unlock', skipOffstage: false);
    expect(hidden, findsOneWidget, reason: 'Settings stays mounted underneath');
    expect(hidden.hitTestable(), findsNothing);

    await tester.tap(hidden, warnIfMissed: false);
    await _settle(tester);
    expect(t.prefs.getBool('app_lock_enabled'), true);

    // Passing the prompt returns to the same page, not to Home.
    t.lock.passes = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await _settle(tester);
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Require unlock'), findsOneWidget);
  });

  testWidgets('turning the lock off needs a passing prompt', (tester) async {
    final t = await _openSettings(tester);

    t.lock.passes = false;
    await tester.tap(find.text('Require unlock'));
    await _settle(tester);
    expect(t.lock.prompts, 2);
    expect(t.prefs.getBool('app_lock_enabled'), true);

    t.lock.passes = true;
    await tester.tap(find.text('Require unlock'));
    await _settle(tester);
    expect(t.prefs.getBool('app_lock_enabled'), false);
  });

  testWidgets('Export data needs a passing prompt while the lock is on', (
    tester,
  ) async {
    final t = await _openSettings(tester);

    t.lock.passes = false;
    await tester.tap(find.text('Export data'));
    await _settle(tester);
    expect(t.lock.prompts, 2);
    expect(t.backup.exports, 0, reason: 'no plaintext file without the check');

    t.lock.passes = true;
    await tester.tap(find.text('Export data'));
    await _settle(tester);
    expect(t.backup.exports, 1);
  });
}
