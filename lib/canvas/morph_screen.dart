import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'blueprint.dart';
import 'canvas_shell.dart' show domainAccent, domainIcon;
import 'canvas_store.dart';
import 'samples.dart';
import 'shaper.dart';

/// Files larger than this are refused before reading.
const _maxFileBytes = 2 * 1024 * 1024;

const _typeLabels = {
  SectionType.checklist: 'checklist',
  SectionType.ledger: 'money',
  SectionType.people: 'who owes whom',
  SectionType.notes: 'note',
  SectionType.goals: 'someday list',
};

/// "Bring your own system": paste or pick what you already keep, see what
/// the app will become, then shape it. Everything runs on the phone.
class MorphScreen extends ConsumerStatefulWidget {
  const MorphScreen({super.key});

  @override
  ConsumerState<MorphScreen> createState() => _MorphScreenState();
}

class _MorphScreenState extends ConsumerState<MorphScreen> {
  final _paste = TextEditingController();
  final _docs = <SourceDoc>[];
  CanvasPreview? _preview;
  bool _busy = false;

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  void _add(Iterable<SourceDoc> docs) {
    setState(() {
      _docs.addAll(docs.where((d) => d.text.trim().isNotEmpty));
      _preview = _docs.isEmpty
          ? null
          : ref.read(canvasProvider.notifier).preview(_docs);
    });
  }

  void _remove(int i) {
    _docs.removeAt(i);
    _add(const []);
  }

  void _addPasted() {
    final text = _paste.text;
    if (text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final n = _docs.where((d) => d.name.startsWith('Pasted')).length + 1;
    _add([SourceDoc(n == 1 ? 'Pasted note' : 'Pasted note $n', text)]);
    _paste.clear();
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickFile() async {
    try {
      final picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Notes and sheets',
            extensions: ['txt', 'md', 'csv', 'tsv'],
            uniformTypeIdentifiers: [
              'public.plain-text',
              'public.comma-separated-values-text',
              'public.tab-separated-values-text',
              'public.text',
            ],
            mimeTypes: ['text/plain', 'text/csv', 'text/markdown'],
          ),
        ],
      );
      if (picked == null) return;
      if (await picked.length() > _maxFileBytes) {
        _say('That file is over 2 MB. Save just the part you use as text.');
        return;
      }
      _add([SourceDoc(picked.name, await picked.readAsString())]);
    } on FormatException {
      _say('That file is not plain text. Export it as .txt or .csv first.');
    } catch (_) {
      _say('Could not open that file.');
    }
  }

  Future<void> _apply() async {
    final p = _preview;
    if (p == null || !p.hasNewSections) return;
    setState(() => _busy = true);
    final written = await writeNewItems(
      ref.read(isarProvider),
      ref.read(syncServiceProvider),
      p.items,
    );
    ref.read(canvasProvider.notifier).commit(p);
    ref.read(canvasTabProvider.notifier).state = null;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Shaped ${p.fresh.fold(0, (a, s) => a + s.sections.length)} '
          'sections, $written rows',
        ),
      ),
    );
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Shape it your way')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
            child: Text(
              'You already keep your life somewhere: a pinned note, a chat '
              'with yourself, a budget sheet. Bring it in and the app takes '
              'its shape, in your order and your words. It is read on this '
              'phone; nothing is sent anywhere.',
              style: context.text.bodyMedium!.copyWith(color: c.inkSub),
            ),
          ),
          groupHeader(context, 'Add'),
          cardGroup(context, [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: TextField(
                controller: _paste,
                minLines: 4,
                maxLines: 10,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Paste a note, a list, a chat with yourself, or a sheet '
                      'copied from Excel…',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _addPasted,
                    icon: const Icon(CupertinoIcons.text_badge_plus, size: 18),
                    label: const Text('Add this text'),
                  ),
                  TextButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(CupertinoIcons.doc, size: 18),
                    label: const Text('From a file'),
                  ),
                  TextButton.icon(
                    onPressed: () => _add(kSampleSources),
                    icon: const Icon(CupertinoIcons.lightbulb, size: 18),
                    label: const Text('Try an example'),
                  ),
                ],
              ),
            ),
          ]),
          if (_docs.isNotEmpty) ...[
            groupHeader(context, 'What you brought'),
            cardGroup(context, [
              for (var i = 0; i < _docs.length; i++) ...[
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_text),
                  title: Text(_docs[i].name),
                  subtitle: Text(
                    _docs[i].text.trim().split('\n').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove ${_docs[i].name}',
                    icon: const Icon(CupertinoIcons.xmark, size: 18),
                    onPressed: () => _remove(i),
                  ),
                ),
                if (i != _docs.length - 1) rowDivider(context),
              ],
            ]),
          ],
          if (p != null) ...[
            groupHeader(context, 'What the app becomes'),
            _PreviewCard(preview: p),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: FilledButton(
            onPressed: (p?.hasNewSections ?? false) && !_busy ? _apply : null,
            child: Text(_busy ? 'Shaping…' : 'Shape my app'),
          ),
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});
  final CanvasPreview preview;

  @override
  Widget build(BuildContext context) {
    final bp = preview.blueprint;
    final freshIds = {
      for (final s in preview.fresh) ...s.sections.map((x) => x.id),
    };
    final headline = !preview.hasNewSections
        ? 'Nothing new to add.'
        : bp.hasNav
        ? '${bp.tabs.length} tabs: ${bp.tabs.map((t) => t.title).join(' · ')}'
        : 'One page, no tabs — like a single pinned note.';
    return cardGroup(context, [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        child: Text(headline, style: context.text.titleSmall),
      ),
      if (preview.alreadyIn > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
          child: Text(
            '${preview.alreadyIn} already in your app — skipped.',
            style: context.text.bodySmall,
          ),
        ),
      for (final t in bp.tabs) ...[
        if (bp.hasNav)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
            child: Row(
              children: [
                IconTile(
                  icon: domainIcon(t.domain),
                  accent: domainAccent(t.domain),
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(t.title, style: context.text.labelLarge),
              ],
            ),
          ),
        for (final s in t.sections)
          Padding(
            padding: EdgeInsets.fromLTRB(bp.hasNav ? 56 : 18, 3, 18, 3),
            child: Text(
              [
                s.title,
                _typeLabels[s.type]!,
                if (freshIds.contains(s.id))
                  '${preview.countIn(s.id)} new'
                else
                  'already here',
              ].join(' · '),
              style: context.text.bodySmall,
            ),
          ),
      ],
      const SizedBox(height: 14),
    ]);
  }
}
