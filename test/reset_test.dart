import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/services/reset_service.dart';
import 'package:life_manager/widgets/delete_everything_dialog.dart';

Future<bool?> showConfirm(WidgetTester tester, {bool cloud = true}) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await showDialog<bool>(
            context: context,
            builder: (_) => DeleteEverythingDialog(cloud: cloud),
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Finder get _deleteButton =>
    find.widgetWithText(FilledButton, 'Delete everything');

bool _enabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_deleteButton).onPressed != null;

void main() {
  group('delete confirmation', () {
    testWidgets('the destructive button starts disabled', (tester) async {
      await showConfirm(tester);

      expect(_deleteButton, findsOneWidget);
      expect(_enabled(tester), isFalse,
          reason: 'an accidental tap must not be able to wipe everything');
    });

    testWidgets('stays disabled for a wrong or partial phrase',
        (tester) async {
      await showConfirm(tester);

      for (final typed in ['D', 'DELET', 'delete everything', 'yes']) {
        await tester.enterText(find.byType(TextField), typed);
        await tester.pump();
        expect(_enabled(tester), isFalse, reason: 'typed "$typed"');
      }
    });

    testWidgets('enables once the phrase is typed', (tester) async {
      await showConfirm(tester);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();

      expect(_enabled(tester), isTrue);
    });

    testWidgets('accepts lowercase and surrounding spaces', (tester) async {
      await showConfirm(tester);

      await tester.enterText(find.byType(TextField), '  delete ');
      await tester.pump();

      expect(_enabled(tester), isTrue,
          reason: 'the guard is against accidents, not a spelling test');
    });

    testWidgets('confirming returns true', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const DeleteEverythingDialog(cloud: true),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('cancelling returns false even with the phrase typed',
        (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => const DeleteEverythingDialog(cloud: true),
              );
            },
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('warns that the cloud and other devices are affected',
        (tester) async {
      await showConfirm(tester, cloud: true);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(text, contains('cloud'));
      expect(text, contains('other'));
      expect(text.toLowerCase(), contains('cannot be undone'));
      expect(text, contains('Export'),
          reason: 'the user should be pointed at a backup before wiping');
    });

    testWidgets('a local-only build does not promise to clear a cloud',
        (tester) async {
      await showConfirm(tester, cloud: false);

      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(text, isNot(contains('cloud')));
      expect(text, contains('this device'));
    });
  });

  group('delete confirmation layout', () {
    // The dialog autofocuses its text field, so the keyboard is up whenever it
    // is on screen. That cut the available height enough to overflow the
    // content off the bottom on a real phone.
    Future<void> pumpAt(
      WidgetTester tester, {
      required Size size,
      double keyboard = 0,
      double textScale = 1.0,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const Scaffold(body: DeleteEverythingDialog(cloud: true)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('fits a small screen with the keyboard up', (tester) async {
      // iPhone SE-ish logical size, with a typical iOS keyboard inset.
      await pumpAt(tester, size: const Size(320, 568), keyboard: 300);

      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a short screen at a large font scale', (tester) async {
      await pumpAt(tester,
          size: const Size(320, 568), keyboard: 300, textScale: 1.8);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the confirm field stays reachable when space is tight',
        (tester) async {
      await pumpAt(tester, size: const Size(320, 568), keyboard: 300);

      // Scrollable, so it may start off-screen — but it must be reachable and
      // usable, otherwise the dialog can never be confirmed on a small phone.
      await tester.ensureVisible(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();

      expect(_enabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('ResetReport', () {
    test('names both places when the cloud was cleared', () {
      const report = ResetReport(
        localItems: 83,
        localHistory: 9,
        cloudItems: 83,
        cloudHistory: 9,
        clearedCloud: true,
      );

      expect(report.summary, contains('83 items'));
      expect(report.summary, contains('9 history'));
      expect(report.summary, contains('cloud'));
    });

    test('does not mention the cloud on a local-only build', () {
      const report = ResetReport(
        localItems: 4,
        localHistory: 0,
        cloudItems: 0,
        cloudHistory: 0,
        clearedCloud: false,
      );

      expect(report.summary, contains('4 items'));
      expect(report.summary, isNot(contains('cloud')));
    });
  });

  group('ResetBlockedException', () {
    test('carries a message safe to show as-is', () {
      const e = ResetBlockedException('Sign in and try again.');

      expect(e.toString(), 'Sign in and try again.');
      // No type names or stack detail leaking into a SnackBar.
      expect(e.toString().toLowerCase(), isNot(contains('exception')));
    });
  });
}
