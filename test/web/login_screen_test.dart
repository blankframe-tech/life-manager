@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/web/login_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool? secure}) => tester.pumpWidget(
    MaterialApp(
      home: LoginScreen(
        onUnlocked: (_) => fail('unlocked'),
        secureContext: secure,
      ),
    ),
  );

  testWidgets('insecure origin: refuses to create a vault', (tester) async {
    await pump(tester, secure: false);
    expect(find.text(LoginScreen.insecureMessage), findsOneWidget);

    await tester.tap(find.text('Create a new vault'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'long enough pass');
    await tester.enterText(find.byType(TextField).at(1), 'long enough pass');
    await tester.tap(find.text('Create vault'));
    await tester.pumpAndSettle();
    expect(find.text(LoginScreen.insecureMessage), findsOneWidget);
  });

  testWidgets('the test runner (localhost) counts as secure', (tester) async {
    await pump(tester);
    expect(find.text(LoginScreen.insecureMessage), findsNothing);
  });
}
