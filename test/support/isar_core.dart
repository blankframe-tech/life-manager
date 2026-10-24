import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';

/// Loads IsarCore for `flutter test`: the macOS dylib shipped in
/// isar_community_flutter_libs, or a download on other hosts.
Future<void> initIsarForTests() async {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map;
  final pkg = (config['packages'] as List).cast<Map>().firstWhere(
    (p) => p['name'] == 'isar_community_flutter_libs',
  );
  final dylib = Uri.parse('.dart_tool/')
      .resolve('${pkg['rootUri']}/')
      .resolve('macos/libisar.dylib')
      .toFilePath();
  await Isar.initializeIsarCore(
    libraries: Platform.isMacOS ? {Abi.current(): dylib} : const {},
    download: !Platform.isMacOS,
  );
}
