import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:life_manager/store/isar_store.dart';
import 'package:life_manager/models/history_event.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:life_manager/vault/vault_provider.dart';
import 'package:life_manager/vault/vault_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/isar_core.dart';

void main() {
  setUpAll(initIsarForTests);

  testWidgets('set up vault: enforces length + confirm, then saves', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('vault_ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final (isar, svc) =
        await tester.runAsync(() async {
              final isar = await Isar.open(
                [ItemSchema, HistoryEventSchema],
                directory: dir.path,
                name: 'ui',
              );
              final svc = VaultService(
                IsarStore(isar),
                prefs: await SharedPreferences.getInstance(),
                documentsDir: () async => dir,
                iterations: 1000,
              );
              return (isar, svc);
            })
            as (Isar, VaultService);
    addTearDown(() => tester.runAsync(() => isar.close()));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [vaultServiceProvider.overrideWithValue(svc)],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: VaultTiles()),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No vault yet'), findsOneWidget);
    expect(find.textContaining('On My iPhone › Life Manager'), findsOneWidget);

    await tester.tap(find.text('Set up vault'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no way to recover'), findsOneWidget);
    expect(find.text('Remember on this iPhone (Keychain)'), findsOneWidget);

    FilledButton create() =>
        tester.widget(find.widgetWithText(FilledButton, 'Create vault'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'short',
    );
    await tester.pump();
    expect(find.textContaining('at least 10 characters'), findsOneWidget);
    expect(create().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'long enough phrase',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm passphrase'),
      'long enough phrasX',
    );
    await tester.pump();
    expect(find.textContaining('don’t match'), findsOneWidget);
    expect(create().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm passphrase'),
      'long enough phrase',
    );
    await tester.pump();
    await tester.tap(find.text('Create vault'));
    await tester.pump();
    // Work started from the tap runs in the test's fake-async zone: real IO
    // completes in runAsync, its continuations run on pump.
    for (var i = 0; i < 200 && svc.lastSavedAt.value == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(svc.isUnlocked, isTrue);
    expect(File('${dir.path}/LifeManager.lmvault').existsSync(), isTrue);
    expect(find.text('Vault unlocked · auto-saves'), findsOneWidget);
    expect(find.text('Save now'), findsOneWidget);
    expect(find.text('Change passphrase'), findsOneWidget);
    svc.dispose();
  });
}
