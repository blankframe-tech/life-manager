import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Seam for the encrypted vault (built separately under `lib/vault/`).
///
/// Settings → Data & Vault calls these. To wire the real vault in, implement
/// [VaultActions] and return it from [vaultActionsProvider] — nothing in the
/// Settings screen needs to change.
abstract class VaultActions {
  const VaultActions();

  /// False hides nothing but marks the tiles "Coming soon".
  bool get available;

  Future<void> saveVault(BuildContext context);
  Future<void> openVault(BuildContext context);
  Future<void> changePassphrase(BuildContext context);
}

/// Placeholder until the vault lands: every action explains itself.
class ComingSoonVault extends VaultActions {
  const ComingSoonVault();

  @override
  bool get available => false;

  Future<void> _soon(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Encrypted vault is coming soon. '
          'Use Export data for a backup today.',
        ),
      ),
    );
  }

  @override
  Future<void> saveVault(BuildContext context) => _soon(context);
  @override
  Future<void> openVault(BuildContext context) => _soon(context);
  @override
  Future<void> changePassphrase(BuildContext context) => _soon(context);
}

final vaultActionsProvider = Provider<VaultActions>(
  (ref) => const ComingSoonVault(),
);
