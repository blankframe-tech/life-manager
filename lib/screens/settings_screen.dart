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
import '../services/settings_service.dart' show BudgetSplit;
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/delete_everything_dialog.dart';
import 'history_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final _salary = TextEditingController(
      text: ref.read(monthlySalaryProvider).toStringAsFixed(0));

  late final _split = ref.read(budgetSplitProvider);
  late final _needsPct =
      TextEditingController(text: _pctText(_split.needs));
  late final _wantsPct =
      TextEditingController(text: _pctText(_split.wants));
  late final _savingsPct =
      TextEditingController(text: _pctText(_split.savings));

  static String _pctText(double frac) => (frac * 100).round().toString();

  /// True while an export/import is in flight, so the tiles can't be tapped
  /// twice and the export shows a spinner.
  bool _busy = false;

  @override
  void dispose() {
    _salary.dispose();
    _needsPct.dispose();
    _wantsPct.dispose();
    _savingsPct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final themeMode = ref.watch(themeModeProvider);
    final sync = ref.watch(syncServiceProvider);
    final online = ref.watch(syncOnlineProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          groupHeader(context, 'Appearance'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.all(16),
              child: CupertinoSlidingSegmentedControl<ThemeMode>(
                groupValue: themeMode,
                children: const {
                  ThemeMode.system: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('System')),
                  ThemeMode.light: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Light')),
                  ThemeMode.dark: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('Dark')),
                },
                onValueChanged: (mode) {
                  if (mode != null) {
                    ref.read(themeModeProvider.notifier).set(mode);
                  }
                },
              ),
            ),
          ]),
          groupHeader(context, 'Budget'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _salary,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly salary (৳)',
                  helperText: 'Used for the budget split below',
                ),
                onSubmitted: _saveSalary,
                onEditingComplete: () => _saveSalary(_salary.text),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(
                      child: _splitField(context, 'Needs %', _needsPct)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _splitField(context, 'Wants %', _wantsPct)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _splitField(context, 'Savings %', _savingsPct)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Builder(builder: (context) {
                final sum = _splitSum();
                final ok = sum == 100;
                return Text(
                  ok
                      ? 'Splits add up to 100%'
                      : 'Splits add up to $sum% — should be 100%',
                  style: TextStyle(
                      fontSize: 12,
                      color: ok ? c.inkSub : AppColors.rose),
                );
              }),
            ),
          ]),
          groupHeader(context, 'Sync'),
          cardGroup(context, [
            ListTile(
              leading: Icon(
                online ? CupertinoIcons.cloud : CupertinoIcons.cloud_bolt,
                color: online ? AppColors.green : c.inkSub,
              ),
              title: Text(online ? 'Online' : 'Offline (local only)'),
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
                  ValueListenableBuilder<String?>(
                    valueListenable: sync.lastError,
                    builder: (context, error, _) => error == null
                        ? const SizedBox.shrink()
                        : Text(
                            'Sync error: $error',
                            style: const TextStyle(color: AppColors.rose),
                          ),
                  ),
                ],
              ),
              trailing: TextButton(
                onPressed: online ? () => _syncNow(context, sync) : null,
                child: const Text('Sync now'),
              ),
            ),
          ]),
          if (SupabaseConfig.isConfigured) ...[
            groupHeader(context, 'Account'),
            cardGroup(context, [
              ListTile(
                leading: const Icon(CupertinoIcons.person_circle),
                title: Text(
                  ref.watch(authStateProvider).valueOrNull?.session?.user.email ??
                      'Signed in',
                ),
                trailing: TextButton(
                  onPressed: () => ref.read(authServiceProvider).signOut(),
                  child: const Text('Sign out'),
                ),
              ),
            ]),
          ],
          groupHeader(context, 'Data'),
          cardGroup(context, [
            ListTile(
              leading: const Icon(CupertinoIcons.square_arrow_up),
              title: const Text('Export data'),
              subtitle: const Text(
                  'Save everything as a JSON file you can keep or move'),
              trailing: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: _busy ? null : _exportData,
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.square_arrow_down),
              title: const Text('Import data'),
              subtitle:
                  const Text('Merge a backup file — nothing is deleted'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: _busy ? null : _importData,
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.trash, color: AppColors.rose),
              title: const Text('Delete all data',
                  style: TextStyle(color: AppColors.rose)),
              subtitle: const Text(
                  'Erase everything here and in the cloud, and sign out'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: _busy ? null : _deleteAllData,
            ),
          ]),
          groupHeader(context, 'Security'),
          cardGroup(context, [_appLockTile(context)]),
          groupHeader(context, 'Activity'),
          cardGroup(context, [
            ListTile(
              leading: const Icon(CupertinoIcons.clock),
              title: const Text('Activity History'),
              subtitle: const Text('Every add, edit, and delete over time'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
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
            Text('${summary.items} items and ${summary.history} history '
                'entries${when == null ? '' : ', saved '
                    '${DateFormat('d MMM yyyy, HH:mm').format(when)}'}.'),
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
        builder: (_) =>
            DeleteEverythingDialog(cloud: SupabaseConfig.isConfigured),
      );

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

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

  void _saveSalary(String text) {
    final v = double.tryParse(text.trim());
    if (v != null && v > 0) {
      ref.read(monthlySalaryProvider.notifier).set(v);
    }
  }

  Widget _splitField(
      BuildContext context, String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _saveSplit(),
      onEditingComplete: _saveSplit,
    );
  }

  int _splitSum() {
    int parse(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    return parse(_needsPct) + parse(_wantsPct) + parse(_savingsPct);
  }

  void _saveSplit() {
    final needs = int.tryParse(_needsPct.text.trim());
    final wants = int.tryParse(_wantsPct.text.trim());
    final savings = int.tryParse(_savingsPct.text.trim());
    if (needs == null ||
        wants == null ||
        savings == null ||
        needs < 0 ||
        wants < 0 ||
        savings < 0) {
      return;
    }
    ref.read(budgetSplitProvider.notifier).set(BudgetSplit(
          needs: needs / 100,
          wants: wants / 100,
          savings: savings / 100,
        ));
    setState(() {});
  }

  Future<void> _syncNow(BuildContext context, SyncService sync) async {
    final result = await sync.forceResync();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.failed == 0
              ? (result.pushed == 0
                  ? 'Already up to date'
                  : 'Synced ${result.pushed} item(s)')
              : 'Synced ${result.pushed}, failed ${result.failed} — see error below',
        ),
      ),
    );
  }
}
