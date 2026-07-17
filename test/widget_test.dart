import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:life_manager/widgets/common.dart';

void main() {
  testWidgets('emptyState renders its title and subtitle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: emptyState(Icons.star, 'Nothing here', 'Add your first item.'),
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add your first item.'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });
}
