import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_manager/app_modules.dart';
import 'package:life_manager/models/item.dart';
import 'package:life_manager/modules/module.dart';
import 'package:life_manager/providers/providers.dart';
import 'package:life_manager/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Item item(
  String kind,
  String title, {
  double? amount,
  String? section,
  String? category,
  String? direction,
  DateTime? due,
  bool done = false,
}) => Item()
  ..uuid = '$kind-$title'
  ..kind = kind
  ..title = title
  ..amount = amount
  ..section = section
  ..category = category
  ..direction = direction
  ..dueDate = due
  ..done = done
  ..updatedAt = DateTime.now().toUtc();

/// Pumps [home] over in-memory items (no Isar), with every module's intro
/// already seen unless [introsSeen] says otherwise.
Future<void> pumpV2(
  WidgetTester tester,
  Widget home, {
  AppConfig config = kAppConfig,
  List<Item> items = const [],
  Map<String, Object> prefs = const {},
  List<String>? introsSeen,
  ThemeData? theme,
}) async {
  SharedPreferences.setMockInitialValues({
    'module_intros_seen': introsSeen ?? [for (final m in config.modules) m.id],
    ...prefs,
  });
  final sp = await SharedPreferences.getInstance();
  final kinds = {
    for (final m in kAppConfig.modules) ...m.items.map((s) => s.kind),
    for (final m in config.modules) ...m.items.map((s) => s.kind),
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        appConfigProvider.overrideWithValue(config),
        for (final k in kinds)
          itemsProvider(k).overrideWith(
            (ref) => Stream.value(items.where((i) => i.kind == k).toList()),
          ),
      ],
      child: MaterialApp(theme: theme ?? buildTheme(), home: home),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
