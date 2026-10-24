import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_modules.dart';
import '../main.dart';
import '../providers/providers.dart';
import '../screens/root_scaffold.dart';
import '../theme/app_theme.dart';
import '../vault/vault_codec.dart';
import '../widgets/leaf_mark.dart';
import 'browser.dart';
import 'guards.dart';
import 'login_screen.dart';
import 'web_vault.dart';

/// The browser app: the login screen while locked, else the V2 app over the
/// unlocked [WebVault], with a bar for sync status, Sync and Lock.
class WebApp extends StatefulWidget {
  const WebApp({super.key});

  @override
  State<WebApp> createState() => _WebAppState();
}

class _WebAppState extends State<WebApp> {
  static const _tickEvery = Duration(seconds: 15);

  WebVault? _vault;
  String? _notice;
  AutoLockPolicy? _policy;
  Timer? _timer;
  SharedPreferences? _prefs;
  GlobalKey<NavigatorState> _navigator = GlobalKey();

  @override
  void initState() {
    super.initState();
    guardUnload(() => _vault?.dirty.value ?? false);
    onVisibilityChange((visible) {
      _policy?.visibilityChanged(visible: visible);
      _check();
    });
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _policy?.activity();
    return false;
  }

  Future<void> _unlocked(WebVault vault) async {
    // Fresh, in-memory preferences per session (see boot_web.dart).
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('onboarding_done_v2', true);
    await prefs.setStringList('module_intros_seen', [
      for (final m in kAppConfig.modules) m.id,
    ]);
    setState(() {
      _vault = vault;
      _prefs = prefs;
      _notice = null;
      _policy = AutoLockPolicy();
      _navigator = GlobalKey();
    });
    _timer = Timer.periodic(_tickEvery, (_) => _check());
  }

  void _check() {
    final reason = _policy?.due();
    if (reason != null) unawaited(lock(reason));
  }

  /// Drops the key and every decrypted row and returns to the login screen.
  /// An automatic lock with unsynced changes saves the encrypted file first
  /// (in place when the browser already allows it, else as a download), so
  /// locking never loses work.
  Future<void> lock(LockReason reason) async {
    final vault = _vault;
    if (vault == null) return;
    _timer?.cancel();
    _policy = null;
    String? saved;
    if (reason != LockReason.manual && vault.dirty.value) {
      try {
        final s = vault.source;
        if (s is HandleSource && await s.hasWritePermission()) {
          await vault.sync();
          saved = 'Your changes were saved to ${s.name}.';
        } else {
          download(await vault.encrypt(), vaultFileName);
          saved =
              'Your unsynced changes were downloaded as $vaultFileName '
              '(encrypted).';
        }
      } catch (_) {
        saved = "Your unsynced changes couldn't be saved.";
      }
    }
    final why = switch (reason) {
      LockReason.manual => 'Locked.',
      LockReason.idle => 'Locked after 10 minutes without activity.',
      LockReason.hidden => 'Locked while the tab was in the background.',
    };
    setState(() {
      _vault = null;
      _notice = [why, ?saved].join(' ');
    });
    await _prefs?.clear();
    // After the frame, so nothing still listening reads a disposed vault.
    WidgetsBinding.instance.addPostFrameCallback((_) => vault.dispose());
  }

  @override
  Widget build(BuildContext context) {
    final vault = _vault;
    if (vault == null) {
      return MaterialApp(
        title: 'Life Manager',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        darkTheme: buildTheme(brightness: Brightness.dark),
        home: LoginScreen(onUnlocked: _unlocked, notice: _notice),
      );
    }
    final navigator = _navigator;
    return Listener(
      onPointerDown: (_) => _policy?.activity(),
      onPointerSignal: (_) => _policy?.activity(),
      onPointerHover: (_) => _policy?.activity(),
      child: ProviderScope(
        // A new scope per session: locking disposes every provider's cache.
        key: ObjectKey(vault),
        overrides: [
          storeProvider.overrideWithValue(vault.store),
          sharedPreferencesProvider.overrideWithValue(_prefs!),
          platformDataTilesProvider.overrideWithValue([
            _VaultFileTile(vault: vault),
          ]),
        ],
        child: LifeManagerApp(
          navigatorKey: navigator,
          home: const RootScaffold(),
          // Laid out bottom-up so the bar paints after the app: the routes
          // block the semantics of anything painted before them, which
          // would hide Sync and Lock from screen readers.
          builder: (context, child) => Column(
            verticalDirection: VerticalDirection.up,
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true, // the bar already sits below the notch
                  child: child!,
                ),
              ),
              _WebBar(
                vault: vault,
                navigator: navigator,
                onLock: () => _confirmLock(navigator),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLock(GlobalKey<NavigatorState> navigator) async {
    final vault = _vault;
    if (vault == null) return;
    if (vault.dirty.value) {
      final ctx = navigator.currentContext;
      if (ctx == null) return;
      final choice = await showDialog<String>(
        context: ctx,
        builder: (ctx) => AlertDialog(
          title: const Text('Lock with unsynced changes?'),
          content: const Text(
            'Changes since your last sync are only in this tab. Locking '
            'without syncing discards them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Lock without syncing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'sync'),
              child: const Text('Sync and lock'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'sync') {
        final ok = await _syncWithFeedback(vault, navigator);
        if (!ok) return;
      }
    }
    await lock(LockReason.manual);
  }
}

/// Runs a sync and tells the user what happened. False if it failed.
Future<bool> _syncWithFeedback(
  WebVault vault,
  GlobalKey<NavigatorState> navigator,
) async {
  String? error;
  try {
    await vault.sync();
  } on VaultException catch (e) {
    error =
        '${e.message} The file on disk changed and could not be merged, so '
        'nothing was written.';
  } catch (e) {
    error = "Couldn't save the vault: $e";
  }
  final ctx = navigator.currentContext;
  if (ctx == null || !ctx.mounted) return error == null;
  if (error != null) {
    await showDialog<void>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync failed'),
        content: Text(error!),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }
  if (!vault.source.writesInPlace) {
    await showDialog<void>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloaded $vaultFileName'),
        content: const Text(
          'Put it back where your iPhone keeps it: save it over the old file '
          'in iCloud Drive › Life Manager, or AirDrop it to your iPhone. The '
          'app merges it when you open it (newer edits win).\n\n'
          'If your browser renamed it (for example "LifeManager (1)"), '
          'rename it back first.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(content: Text('Saved to ${vault.source.name}')),
    );
  }
  return true;
}

/// The strip above every screen: file name, sync state, Sync and Lock.
class _WebBar extends StatefulWidget {
  const _WebBar({
    required this.vault,
    required this.navigator,
    required this.onLock,
  });

  final WebVault vault;
  final GlobalKey<NavigatorState> navigator;
  final VoidCallback onLock;

  @override
  State<_WebBar> createState() => _WebBarState();
}

class _WebBarState extends State<_WebBar> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    await _syncWithFeedback(widget.vault, widget.navigator);
    if (mounted) setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = widget.vault;
    return Material(
      color: c.card,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hair)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              children: [
                const LeafMark(size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    v.source.name,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.labelLarge,
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: v.dirty,
                  builder: (context, dirty, _) => dirty
                      ? Semantics(
                          container: true,
                          liveRegion: true,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: c.negative.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              'Unsynced changes',
                              style: context.text.labelMedium?.copyWith(
                                color: c.negative,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(CupertinoIcons.arrow_2_circlepath, size: 18),
                  label: const Text('Sync'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
                Semantics(
                  container: true,
                  label: 'Lock',
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    onPressed: widget.onLock,
                    icon: const Icon(CupertinoIcons.lock),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Settings → Data & Vault on the web.
class _VaultFileTile extends StatelessWidget {
  const _VaultFileTile({required this.vault});

  final WebVault vault;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DateTime?>(
    valueListenable: vault.lastSyncedAt,
    builder: (context, at, _) => ListTile(
      leading: const Icon(CupertinoIcons.lock_shield),
      title: Text(vault.source.name),
      subtitle: Text(
        [
          vault.source.writesInPlace
              ? 'Sync writes back to this file.'
              : 'Sync downloads the encrypted file; put it back in iCloud '
                    'Drive › Life Manager.',
          at == null
              ? 'Not synced in this session.'
              : 'Last synced ${DateFormat.Hm().format(at)}.',
          'Locks after 10 minutes idle.',
        ].join(' '),
      ),
    ),
  );
}
