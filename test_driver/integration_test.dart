import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes each screenshot to $SHOTS_DIR (default build/screenshots).
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final dir = Platform.environment['SHOTS_DIR'] ?? 'build/screenshots';
    final file = File('$dir/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
