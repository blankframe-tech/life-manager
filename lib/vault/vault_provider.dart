import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'vault_service.dart';

export 'vault_service.dart';

/// The encrypted vault file — Settings → Data & Vault.
final vaultServiceProvider = Provider<VaultService>((ref) {
  final svc = VaultService(
    ref.watch(storeProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    backup: ref.watch(backupServiceProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});
