import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../config/supabase_config.dart';
import '../providers/providers.dart';
import '../services/backup_service.dart';
import '../services/reset_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../vault/vault_ui.dart';
import '../widgets/common.dart';
import '../widgets/delete_everything_dialog.dart';
import 'history_screen.dart';
import '../widgets/leaf_mark.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _name = TextEditingController(text: ref.read(userNameProvider));

  /// True while an export/import is in flight, so the tiles can't be tapped
  /// twice and the export shows a spinner.
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final themeMode = ref.watch(themeModeProvider);
    final sync = ref.watch(syncServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
            child: Row(
              children: [
                const LeafMark(size: 44),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Life Manager', style: context.text.headlineSmall),
                    Text(
                      kIsWeb
                          ? 'Nothing is stored in this browser.'
                          : 'Your data stays on this device.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          groupHeader(context, 'Profile'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  helperText: 'Used in the home greeting',
                ),
                onChanged: (v) => ref.read(userNameProvider.notifier).set(v),
              ),
            ),
          ]),
          groupHeader(context, 'Appearance'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoSlidingSegmentedControl<ThemeMode>(
                groupValue: themeMode,
                children: const {
                  ThemeMode.system: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('System'),
                  ),
                  ThemeMode.light: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Light'),
                  ),
                  ThemeMode.dark: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Dark'),
                  ),
                },
                onValueChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).set(mode);
                  }
                },
              ),
            ),
          ]),
          // Each enabled module may contribute a block (Budget, Transactions…).
          for (final m in ref.watch(appConfigProvider).modules)
            if (m.buildSettings(context) case final block?) ...[
              groupHeader(context, m.title),
              cardGroup(context, [block]),
            ],
          if (!SupabaseConfig.isConfigured) ...[
            groupHeader(context, 'Storage'),
            cardGroup(context, [
              const ListTile(
                leading: Icon(
                  kIsWeb
                      ? CupertinoIcons.lock_shield
                      : CupertinoIcons.device_phone_portrait,
                ),
                title: Text(kIsWeb ? 'In this tab only' : 'On this device only'),
                subtitle: Text(
                  kIsWeb
                      ? 'Your data never leaves this browser except as the '
                            'encrypted file you save.'
                      : 'Nothing leaves your phone. Set up the encrypted '
                            'vault in Data & Vault below.',
                ),
              ),
            ]),
          ],
          if (SupabaseConfig.isConfigured) ...[
            groupHeader(context, 'Sync'),
            cardGroup(context, [
              ValueListenableBuilder<bool>(
                valueListenable: sync.isOnline,
                builder: (context, online, _) => ListTile(
                  leading: Icon(
                    online ? CupertinoIcons.cloud : CupertinoIcons.cloud_bolt,
                    color: online ? c.positive : c.inkSub,
                  ),
                  title: Text(online ? 'Online' : 'Offline'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<DateTime?>(
                        valueListenable: sync.lastSyncedAt,
                        builder: (context, value, _) => Text(
                          value == null
                              ? 'Not synced yet'
                              : 'Last synced ${DateFormat('d MMM, HH:mm').format(value)}',
                        ),
                      ),
                      // Reassurance, not an error: offline is a normal state and
                      // nothing is lost in it.
                      if (!online && sync.enabled)
                        const Text(
                          'Changes are saved here and will sync '
                          'automatically when you reconnect.',
                        ),
                      ValueListenableBuilder<String?>(
                        valueListenable: sync.lastError,
                        builder: (context, error, _) =>
                            error == null || (!online && sync.enabled)
                            ? const SizedBox.shrink()
                            : Text(
                                'Sync error: $error',
                                style: TextStyle(color: c.negative),
                              ),
                      ),
                    ],
                  ),
                  // Gated on `enabled` rather than `online` so someone who knows
                  // their connection is back can skip the 30s retry tick.
                  trailing: TextButton(
                    onPressed: sync.enabled
                        ? () => _syncNow(context, sync)
                        : null,
                    child: const Text('Sync now'),
                  ),
                ),
              ),
            ]),
          ],
          if (SupabaseConfig.isConfigured) ...[
            groupHeader(context, 'Account'),
            cardGroup(context, [
              ListTile(
                leading: const Icon(CupertinoIcons.person_circle),
                title: Text(
                  ref.watch(sessionProvider).session?.user.email ?? 'Signed in',
                ),
                trailing: TextButton(
                  onPressed: () => ref.read(authServiceProvider).signOut(),
                  child: const Text('Sign out'),
                ),
              ),
            ]),
          ],
          groupHeader(context, 'Data & Vault'),
          cardGroup(context, ref.watch(platformDataTilesProvider) ?? [
            ListTile(
              leading: const Icon(CupertinoIcons.square_arrow_up),
              title: const Text('Export data'),
              subtitle: const Text(
                'Save everything as a JSON file you can keep or move',
              ),
              trailing: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: _busy ? null : _exportData,
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.square_arrow_down),
              title: const Text('Import data'),
              subtitle: const Text('Merge a backup file — nothing is deleted'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: _busy ? null : _importData,
            ),
            const VaultTiles(),
            ListTile(
              leading: Icon(CupertinoIcons.trash, color: c.negative),
              title: Text(
                'Delete all data',
                style: TextStyle(color: c.negative),
              ),
              subtitle: const Text(
                'Erase everything here and in the cloud, and sign out',
              ),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: _busy ? null : _deleteAllData,
            ),
          ]),
          // The web locks from its top bar; there is no device passcode.
          if (!kIsWeb) ...[
            groupHeader(context, 'Security'),
            cardGroup(context, [_appLockTile(context)]),
          ],
          groupHeader(context, 'Activity'),
          cardGroup(context, [
            ListTile(
              leading: const Icon(CupertinoIcons.clock),
              title: const Text('Activity History'),
              subtitle: const Text('Every add, edit, and delete over time'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
            ),
          ]),
          groupHeader(context, 'About'),
          cardGroup(context, [
            ListTile(
              leading: const Icon(CupertinoIcons.doc_plaintext),
              title: const Text('Licences'),
              subtitle: const Text('Open-source software and fonts'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Life Manager',
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// Writes a backup and hands it to the system share sheet, which is what
  /// "download" means on a phone — save to Files, AirDrop, mail it to yourself.
  Future<void> _exportData() async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(backupServiceProvider).writeExportFile();
      if (!mounted) return;
      // The share sheet needs an anchor rect on iPad or it throws.
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          fileNameOverrides: [file.path.split('/').last],
          subject: 'Life Manager backup',
          sharePositionOrigin: box == null
              ? null
              : Rect.fromLTWH(0, 0, box.size.width, box.size.height / 2),
        ),
      );
    } catch (e) {
      if (mounted) _toast('Export failed: ${_short(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Picks a backup file, confirms what's in it, then merges.
  Future<void> _importData() async {
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Life Manager backup',
            extensions: ['json'],
            // iOS requires non-empty UTIs and ignores the rest; `public.text`
            // rides along so a backup that arrived via mail or AirDrop with a
            // vaguer type is still selectable. Wrong files are caught by
            // `peek()` with a readable message.
            uniformTypeIdentifiers: ['public.json', 'public.text'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
      if (picked == null) return; // cancelled

      final raw = await picked.readAsString();
      final backup = ref.read(backupServiceProvider);
      // Validates before the user commits — a wrong file fails here, not after.
      final summary = backup.peek(raw);
      if (!mounted) return;

      final confirmed = await _confirmImport(summary);
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      final report = await backup.importJson(raw);
      if (!mounted) return;
      _toast(report.summary);
      // Anything imported is flagged unsynced — get it to the cloud now rather
      // than waiting on the 30s retry.
      if (report.changedAnything) {
        unawaited(ref.read(syncServiceProvider).forceResync());
      }
    } on BackupFormatException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Import failed: ${_short(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmImport(BackupSummary summary) {
    final when = summary.exportedAt;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Same reason as the delete dialog: keep the text reachable on a short
        // screen or at a large font scale rather than clipping it.
        scrollable: true,
        title: const Text('Import this backup?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${summary.items} items and ${summary.history} history '
              'entries${when == null ? '' : ', saved '
                        '${DateFormat('d MMM yyyy, HH:mm').format(when)}'}.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Nothing is deleted. Where the same item exists in both, the '
              'newer version wins — the same rule sync uses.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  /// Wipes everything, everywhere, and signs out. Guarded by a typed
  /// confirmation because it clears the cloud too — an accidental tap here
  /// would take the other device's data with it, and none of it comes back.
  Future<void> _deleteAllData() async {
    final reset = ref.read(resetServiceProvider);
    if (!reset.canReset) {
      _toast('Sign in first — otherwise the cloud copy would sync back.');
      return;
    }
    if (await _confirmDelete() != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final report = await reset.wipeEverything();
      if (!mounted) return;
      // Re-read every preference-backed provider now that the store is empty,
      // so the UI drops to defaults instead of showing cleared values.
      ref.invalidate(themeModeProvider);
      ref.invalidate(monthlySalaryProvider);
      ref.invalidate(budgetSplitProvider);
      ref.invalidate(appLockEnabledProvider);
      // The SnackBar comes from the root messenger above AuthGate, so it
      // survives the sign-out swapping this screen for the sign-in screen.
      _toast(report.summary);
      await ref.read(authServiceProvider).signOut();
    } on ResetBlockedException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('Delete failed: ${_short(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDelete() => showDialog<bool>(
    context: context,
    builder: (_) => DeleteEverythingDialog(cloud: SupabaseConfig.isConfigured),
  );

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  /// Keeps raw platform/plugin detail out of a SnackBar in release builds.
  static String _short(Object e) =>
      kDebugMode ? e.toString() : 'please try again';

  /// App lock switch. Disabled when the device has no biometrics and no
  /// passcode, and enabling it requires passing the prompt once — otherwise a
  /// user could flip it on and be locked out by a sensor that never works.
  Widget _appLockTile(BuildContext context) {
    final enabled = ref.watch(appLockEnabledProvider);
    final available = ref.watch(appLockAvailableProvider).valueOrNull ?? false;
    return SwitchListTile.adaptive(
      secondary: const Icon(CupertinoIcons.lock_shield),
      title: const Text('Require unlock'),
      subtitle: Text(
        available
            ? 'Ask for biometrics or your passcode when the app opens'
            : 'Unavailable — set up biometrics or a device passcode first',
      ),
      value: enabled && available,
      onChanged: available ? _setAppLock : null,
    );
  }

  Future<void> _setAppLock(bool value) async {
    final notifier = ref.read(appLockEnabledProvider.notifier);
    if (!value) {
      // Turning it off is guarded by the lock screen itself — reaching Settings
      // already required unlocking, so no second prompt here.
      notifier.set(false);
      return;
    }
    final ok = await ref.read(appLockServiceProvider).authenticate();
    if (!mounted) return;
    if (ok) {
      notifier.set(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Left off — the check didn\'t pass')),
      );
    }
  }

  Future<void> _syncNow(BuildContext context, SyncService sync) async {
    final result = await sync.forceResync();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          // Being offline isn't a failure to report as one — nothing was lost
          // and no action is needed, so say that rather than "failed N".
          !sync.reachable
              ? 'Still offline — your changes are saved and will sync '
                    'automatically'
              : result.failed == 0
              ? (result.pushed == 0
                    ? 'Already up to date'
                    : 'Synced ${result.pushed} item(s)')
              : 'Synced ${result.pushed}, failed ${result.failed} — see error below',
        ),
      ),
    );
  }
}
