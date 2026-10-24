import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// `.lmvault` files opened from Files or AirDrop (see `VaultOpenIn` in
/// ios/Runner/AppDelegate.swift). iOS copies each into tmp; [pending] holds
/// the latest copy until the UI shows the "Open vault" sheet and clears it.
class VaultOpenIn {
  static const _channel = MethodChannel('life_manager/vault_open_in');

  static final pending = ValueNotifier<File?>(null);
  static bool _started = false;

  /// Call once at launch. Collects files that opened the app (cold start) and
  /// listens for later ones (warm start).
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') pending.value = File(call.arguments as String);
    });
    try {
      final cold = await _channel.invokeListMethod<String>('ready') ?? [];
      if (cold.isNotEmpty) pending.value = File(cold.last);
    } on MissingPluginException {
      // Android, tests: no open-in handler.
    }
  }
}
