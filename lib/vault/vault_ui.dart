import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'vault_open_in.dart';
import 'vault_provider.dart';

/// New passphrases must be at least this long.
const kMinPassphraseLength = 10;

/// Where iOS shows the vault, for the status row.
const kVaultLocation = 'On My iPhone › Life Manager › ${VaultService.fileName}';

enum _Mode { setUp, unlock, change }

typedef PassphraseResult = ({
  String? current,
  String passphrase,
  bool remember,
});

Future<PassphraseResult?> _passphraseSheet(
  BuildContext context,
  _Mode mode, {
  String? title,
  String? subtitle,
}) => showModalBottomSheet<PassphraseResult>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      _PassphraseSheet(mode: mode, title: title, subtitle: subtitle),
);

class _PassphraseSheet extends StatefulWidget {
  const _PassphraseSheet({required this.mode, this.title, this.subtitle});
  final _Mode mode;
  final String? title;
  final String? subtitle;

  @override
  State<_PassphraseSheet> createState() => _PassphraseSheetState();
}

class _PassphraseSheetState extends State<_PassphraseSheet> {
  final _current = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _remember = false;
  bool _obscure = true;

  bool get _isNew => widget.mode != _Mode.unlock;

  @override
  void dispose() {
    _current.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? get _problem {
    if (widget.mode == _Mode.change && _current.text.isEmpty) {
      return 'Enter your current passphrase.';
    }
    if (_pass.text.isEmpty) return 'Enter a passphrase.';
    if (!_isNew) return null;
    if (_pass.text.length < kMinPassphraseLength) {
      return 'Use at least $kMinPassphraseLength characters '
          '(${_pass.text.length} so far). A few unrelated words work well.';
    }
    if (_confirm.text != _pass.text) return 'The two passphrases don’t match.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problem = _problem;
    final title =
        widget.title ??
        switch (widget.mode) {
          _Mode.setUp => 'Set up vault',
          _Mode.unlock => 'Unlock vault',
          _Mode.change => 'Change passphrase',
        };
    Widget field(
      TextEditingController ctl,
      String label, {
      bool autofocus = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctl,
        autofocus: autofocus,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // Material, not a coloured Container, so the Keychain switch's ink shows.
      child: Material(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: c.hair,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Text(title, style: context.text.headlineSmall),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle!,
                      style: context.text.bodyMedium!.copyWith(color: c.inkSub),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (widget.mode == _Mode.change)
                    field(_current, 'Current passphrase', autofocus: true),
                  field(
                    _pass,
                    widget.mode == _Mode.change
                        ? 'New passphrase'
                        : 'Passphrase',
                    autofocus: widget.mode != _Mode.change,
                  ),
                  if (_isNew) field(_confirm, 'Confirm passphrase'),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 18,
                      ),
                      label: Text(_obscure ? 'Show' : 'Hide'),
                    ),
                  ),
                  if (_isNew) ...[
                    Text(
                      problem ?? 'Looks good.',
                      style: context.text.bodySmall!.copyWith(
                        color: problem == null ? c.positive : c.inkSub,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.hair),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            color: c.negative,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'There is no way to recover a lost passphrase. '
                              'Without it, the vault file can’t be opened by '
                              'anyone, including you. Write it down somewhere safe.',
                              style: context.text.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (widget.mode != _Mode.change)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Remember on this iPhone (Keychain)'),
                      subtitle: const Text(
                        'Unlocks automatically when the app opens. '
                        'Never leaves this device.',
                      ),
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: problem != null
                        ? null
                        : () => Navigator.of(context).pop((
                            current: widget.mode == _Mode.change
                                ? _current.text
                                : null,
                            passphrase: _pass.text,
                            remember: _remember,
                          )),
                    child: Text(switch (widget.mode) {
                      _Mode.setUp => 'Create vault',
                      _Mode.unlock => 'Unlock',
                      _Mode.change => 'Change passphrase',
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

String _describe(Object e) => switch (e) {
  VaultException() => e.message,
  StateError() => e.message,
  _ => kDebugMode ? e.toString() : 'Something went wrong. Please try again.',
};

/// Asks for the passphrase of [file] and merges it in. Used by "Open vault
/// file" and by files opened from Files / AirDrop.
Future<void> openVaultFileFlow(
  BuildContext context,
  WidgetRef ref,
  File file,
) async {
  final svc = ref.read(vaultServiceProvider);
  final r = await _passphraseSheet(
    context,
    _Mode.unlock,
    title: 'Open vault',
    subtitle:
        'Merges ${file.uri.pathSegments.last} into this phone. '
        'Newer edits win; nothing is deleted.',
  );
  if (r == null || !context.mounted) return;
  try {
    final report = await svc.openVault(
      file,
      r.passphrase,
      remember: r.remember,
    );
    if (context.mounted) _toast(context, report.summary);
  } catch (e) {
    if (context.mounted) _toast(context, _describe(e));
  }
}

/// Settings → Data & Vault rows: status plus actions.
class VaultTiles extends ConsumerStatefulWidget {
  const VaultTiles({super.key});

  @override
  ConsumerState<VaultTiles> createState() => _VaultTilesState();
}

class _VaultTilesState extends ConsumerState<VaultTiles> {
  /// Prompt to unlock once per app run, not every time Settings opens.
  static bool _prompted = false;

  bool _busy = false;
  bool _exists = false;

  VaultService get _svc => ref.read(vaultServiceProvider);

  @override
  void initState() {
    super.initState();
    _refresh(promptIfLocked: true);
  }

  Future<void> _refresh({bool promptIfLocked = false}) async {
    final exists = await _svc.exists;
    if (!mounted) return;
    setState(() => _exists = exists);
    if (promptIfLocked && exists && !_svc.isUnlocked && !_prompted) {
      _prompted = true;
      await _unlock();
    }
  }

  /// Runs [op] with a spinner and turns failures into a SnackBar.
  Future<void> _run(Future<String?> Function() op) async {
    setState(() => _busy = true);
    try {
      final msg = await op();
      if (mounted && msg != null) _toast(context, msg);
    } catch (e) {
      if (mounted) _toast(context, _describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _setUp() async {
    final r = await _passphraseSheet(context, _Mode.setUp);
    if (r == null) return;
    await _run(() async {
      await _svc.saveVault(r.passphrase, remember: r.remember);
      return 'Vault saved. It now updates itself after every change.';
    });
  }

  Future<void> _unlock() async {
    final r = await _passphraseSheet(
      context,
      _Mode.unlock,
      subtitle: 'Enter the passphrase for ${VaultService.fileName}.',
    );
    if (r == null) return;
    await _run(() async {
      final report = await _svc.openVault(
        await _svc.vaultFile,
        r.passphrase,
        remember: r.remember,
      );
      return 'Unlocked. ${report.summary}';
    });
  }

  Future<void> _openFile() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Life Manager vault',
          extensions: ['lmvault'],
          // Files that arrived without our UTI still show; the codec rejects
          // anything that isn't a vault with a readable message.
          uniformTypeIdentifiers: [
            'tech.blankframe.lifeManager.vault',
            'public.data',
          ],
        ),
      ],
    );
    if (picked == null || !mounted) return;
    await openVaultFileFlow(context, ref, File(picked.path));
    await _refresh();
  }

  Future<void> _change() async {
    final r = await _passphraseSheet(context, _Mode.change);
    if (r == null) return;
    await _run(() async {
      await _svc.changePassphrase(r.current!, r.passphrase);
      return 'Passphrase changed.';
    });
  }

  Future<void> _lock() async {
    final remembered = await _svc.remembered;
    if (!mounted) return;
    final forget = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Lock vault?'),
        content: Text(
          'Auto-save stops until you unlock again. Your data on this phone '
          'stays.${remembered ? ' The passphrase is remembered in the '
                    'Keychain, so the vault unlocks again next launch unless '
                    'you forget it.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (remembered)
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Lock and forget'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Lock'),
          ),
        ],
      ),
    );
    if (forget == null) return;
    await _run(() async {
      await _svc.lock(forget: forget);
      return forget ? 'Locked, and removed from the Keychain.' : 'Locked.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final svc = ref.watch(vaultServiceProvider);
    Widget tile(
      IconData icon,
      String title,
      VoidCallback onTap, {
      String? sub,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: sub == null ? null : Text(sub),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 18),
      onTap: _busy ? null : onTap,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: svc.unlocked,
      builder: (context, unlocked, _) => Column(
        children: [
          ListTile(
            leading: Icon(
              unlocked ? CupertinoIcons.lock_open : CupertinoIcons.lock,
              color: unlocked ? c.positive : c.inkSub,
            ),
            title: Text(
              unlocked
                  ? 'Vault unlocked · auto-saves'
                  : _exists
                  ? 'Vault locked'
                  : 'No vault yet',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<DateTime?>(
                  valueListenable: svc.lastSavedAt,
                  builder: (context, at, _) => Text(
                    at != null
                        ? 'Last saved ${DateFormat('d MMM, HH:mm').format(at.toLocal())}'
                        : unlocked
                        ? 'Not saved this session yet'
                        : 'An encrypted file with all your data',
                  ),
                ),
                Text(kVaultLocation, style: TextStyle(color: c.inkSub)),
                ValueListenableBuilder<Object?>(
                  valueListenable: svc.lastError,
                  builder: (context, error, _) => error == null
                      ? const SizedBox.shrink()
                      : Text(
                          'Auto-save failed: ${_describe(error)}',
                          style: TextStyle(color: c.negative),
                        ),
                ),
              ],
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          rowDivider(context),
          if (!unlocked && !_exists)
            tile(
              CupertinoIcons.lock_rotation,
              'Set up vault',
              _setUp,
              sub: 'Protect everything with a passphrase',
            ),
          if (!unlocked && _exists)
            tile(CupertinoIcons.lock_open, 'Unlock vault', _unlock),
          if (unlocked)
            tile(
              CupertinoIcons.floppy_disk,
              'Save now',
              () => _run(() async {
                await _svc.saveNow();
                return 'Vault saved.';
              }),
            ),
          tile(
            CupertinoIcons.folder_open,
            'Open vault file',
            _openFile,
            sub: 'Merge a .lmvault from Files or the web app',
          ),
          if (unlocked) ...[
            tile(
              CupertinoIcons.textformat_abc_dottedunderline,
              'Change passphrase',
              _change,
            ),
            tile(CupertinoIcons.lock, 'Lock vault', _lock),
          ],
        ],
      ),
    );
  }
}

/// App-root companion: unlocks silently from the Keychain at launch, and shows
/// the "Open vault" sheet for `.lmvault` files opened from Files or AirDrop.
/// Never blocks the app: local use works whether or not the vault unlocks.
class VaultGate extends ConsumerStatefulWidget {
  const VaultGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<VaultGate> createState() => _VaultGateState();
}

class _VaultGateState extends ConsumerState<VaultGate> {
  static bool _triedKeychain = false;

  @override
  void initState() {
    super.initState();
    if (!_triedKeychain) {
      _triedKeychain = true;
      // A wrong remembered passphrase just leaves it locked; Settings asks.
      unawaited(
        ref
            .read(vaultServiceProvider)
            .unlockFromKeychain()
            .catchError((_) => false),
      );
    }
    VaultOpenIn.pending.addListener(_onOpenIn);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenIn());
  }

  @override
  void dispose() {
    VaultOpenIn.pending.removeListener(_onOpenIn);
    super.dispose();
  }

  void _onOpenIn() {
    final file = VaultOpenIn.pending.value;
    if (file == null || !mounted) return;
    VaultOpenIn.pending.value = null;
    openVaultFileFlow(context, ref, file);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
