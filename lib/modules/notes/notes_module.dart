import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/item.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/item_editor.dart';
import '../module.dart';

/// Free-form notes: a title and a body, newest first.
class NotesModule extends LifeModule {
  const NotesModule();

  @override
  String get id => 'notes';
  @override
  String get title => 'Notes';
  @override
  IconData get icon => CupertinoIcons.doc_text;
  @override
  ModuleAccent get accent => Accents.peach;

  @override
  List<ItemSpec> get items => const [
    ItemSpec(
      kind: ItemKind.note,
      singular: 'Note',
      noteHint: 'Write something…',
      noteLines: 10,
    ),
  ];

  @override
  ModuleIntro get intro => const ModuleIntro(
    tagline: 'Capture it before it slips away.',
    description:
        'Ideas, recipes, plans, the name of that book — keep them all in one quiet place.',
    features: [
      IntroFeature(
        CupertinoIcons.pencil,
        'Quick capture',
        'A title and a few lines is all it takes.',
      ),
      IntroFeature(
        CupertinoIcons.search,
        'Instant search',
        'Find any note by a word inside it.',
      ),
      IntroFeature(
        CupertinoIcons.clock,
        'Newest first',
        'What you wrote last is right on top.',
      ),
      IntroFeature(
        CupertinoIcons.lock_shield,
        'Private',
        'Stored on this device only.',
      ),
    ],
  );

  @override
  Widget buildScreen(BuildContext context) => const NotesScreen();
}

final _stamp = DateFormat('d MMM');

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(ItemKind.note));
    final query = ref.watch(searchQueryProvider(ItemKind.note));
    return async.when(
      loading: instantLoading,
      error: (e, _) => errorState(
        context,
        () => ref.invalidate(itemsProvider(ItemKind.note)),
      ),
      data: (all) {
        final notes = filterBySearch(all, query)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        if (notes.isEmpty) {
          return query.trim().isNotEmpty
              ? emptyState(
                  CupertinoIcons.search,
                  'No matches',
                  'No note mentions "${query.trim()}".',
                  accent: Accents.peach,
                )
              : emptyState(
                  CupertinoIcons.doc_text,
                  'A blank page, waiting',
                  'Jot down a thought, a plan or a recipe. Future you will thank you.',
                  onAction: () => showItemEditor(context, ref, ItemKind.note),
                  actionLabel: 'Write a note',
                  accent: Accents.peach,
                );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          itemCount: notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _NoteCard(note: notes[i]),
        );
      },
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});
  final Item note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DeletableRow(
        item: note,
        semanticLabel: '${note.title}. ${note.note}',
        child: Material(
          color: c.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: c.hair),
          ),
          child: InkWell(
            onTap: () =>
                showItemEditor(context, ref, ItemKind.note, existing: note),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          note.title,
                          style: context.text.titleLarge!.copyWith(
                            fontSize: 19,
                          ),
                        ),
                      ),
                      Text(
                        _stamp.format(note.updatedAt.toLocal()),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                  if (note.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      note.note,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium!.copyWith(color: c.inkSub),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
