import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../vault/vault_codec.dart';
import '../widgets/leaf_mark.dart';
import 'browser.dart';
import 'guards.dart';
import 'web_vault.dart';

/// The web "login": pick the `.lmvault` file and enter its passphrase, or
/// start a new vault. Decryption happens here, in the browser.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onUnlocked, this.notice});

  final void Function(WebVault vault) onUnlocked;

  /// Shown above the form, e.g. why the vault locked itself.
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Lives as long as the page, so reopening the form doesn't reset it.
  static final _throttle = PassphraseThrottle();

  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  final _passFocus = FocusNode();
  bool _creating = false;
  bool _busy = false;
  String? _error;
  PickedVault? _picked;
  String? _pickedName;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _startTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pass.dispose();
    _confirm.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  /// Re-renders the backoff countdown once a second while it runs.
  void _startTick() {
    _tick?.cancel();
    if (_throttle.wait == Duration.zero) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_throttle.wait == Duration.zero) t.cancel();
      if (mounted) setState(() {});
    });
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final picked = await pickVault();
      if (picked == null || !mounted) return;
      VaultCodec.parse(picked.bytes); // reject a non-vault before the KDF
      setState(() {
        _picked = picked;
        _pickedName = picked.source.name;
      });
      _passFocus.requestFocus();
    } on VaultException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't read that file.");
    }
  }

  Future<void> _open() async {
    final picked = _picked;
    if (picked == null) {
      setState(() => _error = 'Choose your vault file first.');
      return;
    }
    if (_pass.text.isEmpty || _throttle.wait > Duration.zero) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final vault = await WebVault.open(
        Uint8List.fromList(picked.bytes),
        _pass.text,
        picked.source,
        modified: picked.modified,
      );
      _throttle.succeed();
      _pass.clear();
      widget.onUnlocked(vault);
    } on VaultAuthException {
      _throttle.fail();
      _pass.clear();
      _startTick();
      if (mounted) {
        setState(() => _error = 'Wrong passphrase, or the file was modified.');
      }
    } on VaultException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open that vault.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final p = _pass.text;
    if (p.length < WebVault.minPassphraseLength) {
      setState(
        () => _error =
            'Use at least ${WebVault.minPassphraseLength} characters.',
      );
      return;
    }
    if (p != _confirm.text) {
      setState(() => _error = "The passphrases don't match.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final vault = await WebVault.create(p, NewFileSource());
      _pass.clear();
      _confirm.clear();
      widget.onUnlocked(vault);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final wait = _throttle.wait;
    final waiting = wait > Duration.zero;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: LeafMark(size: 72)),
                    const SizedBox(height: 18),
                    Text(
                      'Life Manager',
                      textAlign: TextAlign.center,
                      style: t.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _creating ? 'Create a new vault' : 'Open your vault',
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(color: c.inkSub),
                    ),
                    if (widget.notice case final notice?) ...[
                      const SizedBox(height: 16),
                      _Note(icon: CupertinoIcons.lock, text: notice),
                    ],
                    const SizedBox(height: 24),
                    if (!_creating) ...[
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Icon(CupertinoIcons.doc),
                        label: Text(
                          _pickedName ?? 'Choose vault file…',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _pass,
                      focusNode: _passFocus,
                      obscureText: true,
                      enabled: !_busy,
                      autofillHints: _creating
                          ? const [AutofillHints.newPassword]
                          : const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Passphrase',
                        helperText: _creating
                            ? 'At least ${WebVault.minPassphraseLength} '
                                  "characters. It can't be recovered."
                            : null,
                      ),
                      onSubmitted: (_) => _creating ? null : _open(),
                    ),
                    if (_creating) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirm,
                        obscureText: true,
                        enabled: !_busy,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Confirm passphrase',
                        ),
                        onSubmitted: (_) => _create(),
                      ),
                    ],
                    if (_error != null || waiting) ...[
                      const SizedBox(height: 12),
                      Text(
                        [
                          ?_error,
                          if (waiting)
                            'Try again in ${wait.inSeconds + 1} s.',
                        ].join(' '),
                        style: t.bodyMedium?.copyWith(color: c.negative),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy || (waiting && !_creating)
                          ? null
                          : (_creating ? _create : _open),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_creating ? 'Create vault' : 'Open'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _creating = !_creating;
                              _error = null;
                              _pass.clear();
                              _confirm.clear();
                            }),
                      child: Text(
                        _creating
                            ? 'I already have a vault'
                            : 'Create a new vault',
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _Note(
                      icon: CupertinoIcons.lock_shield,
                      text:
                          'Privacy: your data never leaves this browser '
                          'except as the encrypted file you save.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}
