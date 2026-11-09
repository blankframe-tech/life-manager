import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../modules/category/category_module.dart';
import '../modules/category/category_screen.dart' show CategoryItemRow;
import '../providers/providers.dart';
import '../screens/more_screen.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/app_nav_bar.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import 'blueprint.dart';
import 'morph_screen.dart';
import 'shaper.dart';

IconData domainIcon(Domain d) => switch (d) {
  Domain.money => CupertinoIcons.money_dollar_circle,
  Domain.people => CupertinoIcons.person_2,
  Domain.todo => CupertinoIcons.checkmark_square,
  Domain.shopping => CupertinoIcons.cart,
  Domain.goals => CupertinoIcons.sparkles,
  Domain.notes => CupertinoIcons.doc_text,
};

ModuleAccent domainAccent(Domain d) => switch (d) {
  Domain.money => Accents.butter,
  Domain.people => Accents.sky,
  Domain.todo => Accents.lavender,
  Domain.shopping => Accents.rose,
  Domain.goals => Accents.sage,
  Domain.notes => Accents.peach,
};

/// The app drawn from the saved [Blueprint]: one page with no bottom nav, or
/// two to six tabs.
class CanvasShell extends ConsumerWidget {
  const CanvasShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(canvasProvider).blueprint?.tabs ?? const [];
    if (tabs.isEmpty) {
      // Every section hidden: say so, and offer the way back.
      return Scaffold(
        appBar: canvasAppBar(context, ref, 'Life'),
        body: emptyState(
          CupertinoIcons.eye_slash,
          'Nothing showing',
          'Every section is hidden.',
          onAction: () => ref.read(canvasProvider.notifier).unhideAll(),
          actionLabel: 'Show them again',
        ),
      );
    }
    if (tabs.length == 1) return CanvasPage(tab: tabs.single);

    final selected = ref.watch(canvasTabProvider);
    final index = tabs.indexWhere((t) => t.id == selected).clamp(0, 99);
    return Scaffold(
      body: tabStack(index, [
        for (final t in tabs) CanvasPage(key: ValueKey(t.id), tab: t),
      ]),
      bottomNavigationBar: AppNavBar(
        selectedIndex: index,
        onSelected: (i) =>
            ref.read(canvasTabProvider.notifier).state = tabs[i].id,
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(domainIcon(t.domain)),
              label: t.title,
            ),
        ],
      ),
    );
  }
}

/// App bar shared by every canvas page: add more material, and a menu for
/// hidden sections, modules and settings.
AppBar canvasAppBar(BuildContext context, WidgetRef ref, String title) {
  final hidden = ref.watch(canvasProvider).hiddenSections.length;
  return AppBar(
    title: Text(title),
    actions: [
      IconButton(
        tooltip: 'Bring in more of your notes',
        icon: const Icon(CupertinoIcons.wand_stars, size: 22),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MorphScreen())),
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
        onSelected: (v) {
          if (v == 'unhide') {
            ref.read(canvasProvider.notifier).unhideAll();
          } else if (v == 'more') {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MoreScreen()));
          }
        },
        itemBuilder: (_) => [
          if (hidden > 0)
            PopupMenuItem(
              value: 'unhide',
              child: Text(
                'Show $hidden hidden section${hidden == 1 ? '' : 's'}',
              ),
            ),
          const PopupMenuItem(
            value: 'more',
            child: Text('Modules, history & settings'),
          ),
        ],
      ),
      const SizedBox(width: 4),
    ],
  );
}

/// One tab: a "jot anything" field, then its sections in the user's order.
class CanvasPage extends ConsumerWidget {
  const CanvasPage({super.key, required this.tab});
  final CanvasTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: canvasAppBar(context, ref, tab.title),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _JotField(sections: tab.sections),
          for (final s in tab.sections)
            CanvasSectionView(key: ValueKey(s.id), section: s),
        ],
      ),
    );
  }
}

/// One line in, routed to the section it fits — the fastest way to update,
/// like adding a line to a pinned note.
class _JotField extends ConsumerStatefulWidget {
  const _JotField({required this.sections});
  final List<SectionSpec> sections;

  @override
  ConsumerState<_JotField> createState() => _JotFieldState();
}

class _JotFieldState extends ConsumerState<_JotField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    final line = text.trim();
    final target = Shaper.route(line, widget.sections);
    if (line.isEmpty || target == null) return;
    HapticFeedback.lightImpact();
    await ref.read(syncServiceProvider).save(Shaper.quickItem(line, target));
    _ctrl.clear();
    _focus.requestFocus();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Added to ${target.title}')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Jot anything — it finds its place',
          prefixIcon: Icon(CupertinoIcons.pencil, size: 20),
        ),
        onSubmitted: _submit,
      ),
    );
  }
}

/// One section: its header with a live summary, its rows, and an add field.
/// Rows are `Item`s with the section's kind and `section == id`, so the
/// classic module screens show the same rows.
class CanvasSectionView extends ConsumerWidget {
  const CanvasSectionView({super.key, required this.section});
  final SectionSpec section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = section;
    final all = ref.watch(itemsProvider(s.kind)).valueOrNull ?? const <Item>[];
    final rows = all.where((i) => i.section == s.id).toList()
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final module = CategoryModule(
      id: s.id,
      kind: s.kind,
      title: s.title,
      singular: 'item',
      icon: domainIcon(s.domain),
      accent: domainAccent(s.domain),
    );
    Widget row(Item i) => switch (s.type) {
      SectionType.notes => _NoteRow(item: i, sectionTitle: s.title),
      SectionType.people => _PersonRow(item: i),
      _ => CategoryItemRow(module: module, item: i),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(section: s, summary: summarize(s, rows)),
        cardGroup(context, [
          for (final i in rows) ...[row(i), rowDivider(context)],
          _AddRow(section: s),
        ]),
      ],
    );
  }
}

/// The header's one-line summary, computed from the live rows.
String summarize(SectionSpec s, List<Item> rows) {
  final open = rows.where((i) => !i.done).toList();
  double sum(Iterable<Item> xs) => xs.fold(0, (a, i) => a + (i.amount ?? 0));
  switch (s.type) {
    case SectionType.notes:
      return '';
    case SectionType.people:
      final net =
          sum(open.where((i) => i.direction == DealDirection.theyOweMe)) -
          sum(open.where((i) => i.direction == DealDirection.iOweThem));
      if (net == 0) return open.isEmpty ? 'all settled' : 'even';
      return net > 0 ? 'owed ${money(net)}' : 'you owe ${money(-net)}';
    case SectionType.ledger:
      if (s.kind == ItemKind.txn) {
        final net = rows.fold<double>(0, (a, i) => a + i.signedAmount);
        return '${net < 0 ? '−' : '+'}${money(net.abs())}';
      }
      return money(sum(rows));
    case SectionType.checklist || SectionType.goals:
      final left = '${open.length} left';
      final cost = sum(open);
      return cost > 0 ? '$left · ${money(cost)}' : left;
  }
}

class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({required this.section, required this.summary});
  final SectionSpec section;
  final String summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final style = context.text.labelMedium!.copyWith(
      color: c.inkSub,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    final canMove = ref.watch(
      canvasProvider.select((s) => s.blueprint?.hasNav ?? false),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 6, 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(section.title.toUpperCase(), style: style),
            ),
          ),
          if (summary.isNotEmpty) Text(summary, style: style),
          PopupMenuButton<String>(
            tooltip: 'Options for ${section.title}',
            icon: Icon(CupertinoIcons.ellipsis, size: 18, color: c.inkSub),
            onSelected: (v) => switch (v) {
              'rename' => _rename(context, ref),
              'move' => _move(context, ref),
              _ => ref.read(canvasProvider.notifier).hide(section.id),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename')),
              if (canMove)
                const PopupMenuItem(value: 'move', child: Text('Move to tab…')),
              const PopupMenuItem(value: 'hide', child: Text('Hide')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: section.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename section'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (title != null) {
      ref.read(canvasProvider.notifier).rename(section.id, title);
    }
  }

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    final domain = await showDialog<Domain>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Move ${section.title} to'),
        children: [
          for (final d in Domain.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Row(
                children: [
                  Icon(domainIcon(d), size: 20),
                  const SizedBox(width: 12),
                  Text(kDomainTitles[d]!),
                ],
              ),
            ),
        ],
      ),
    );
    if (domain != null) {
      ref.read(canvasProvider.notifier).moveTo(section.id, domain);
    }
  }
}

/// "Add to Bazaar list…": one line, parsed with the import rules, so
/// "Eggs 120" gets its price and "Rahim owes me 500" its direction.
class _AddRow extends ConsumerStatefulWidget {
  const _AddRow({required this.section});
  final SectionSpec section;

  @override
  ConsumerState<_AddRow> createState() => _AddRowState();
}

class _AddRowState extends ConsumerState<_AddRow> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    if (text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    await ref
        .read(syncServiceProvider)
        .save(Shaper.quickItem(text.trim(), widget.section));
    _ctrl.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        textInputAction: TextInputAction.done,
        textCapitalization: TextCapitalization.sentences,
        style: context.text.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Add to ${widget.section.title}…',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          prefixIcon: Icon(CupertinoIcons.add, size: 18, color: c.inkSub),
        ),
        onSubmitted: _submit,
      ),
    );
  }
}

class _NoteRow extends ConsumerWidget {
  const _NoteRow({required this.item, required this.sectionTitle});
  final Item item;

  /// An imported note is titled after its heading; don't say it twice.
  final String sectionTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return DeletableRow(
      item: item,
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: () => showItemEditor(context, ref, item.kind, existing: item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title != sectionTitle || item.note.isEmpty)
                  Text(item.title, style: context.text.titleSmall),
                if (item.note.isNotEmpty) ...[
                  if (item.title != sectionTitle) const SizedBox(height: 4),
                  Text(
                    item.note,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyMedium!.copyWith(color: c.inkSub),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.item});
  final Item item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final owedToMe = item.direction == DealDirection.theyOweMe;
    final what = owedToMe ? 'owes you' : 'you owe';
    final tone = item.done ? c.inkSub : (owedToMe ? c.positive : c.negative);
    return DeletableRow(
      item: item,
      semanticLabel: [
        item.title,
        what,
        if (item.amount != null) money(item.amount),
        if (item.done) 'settled',
      ].join(', '),
      child: Material(
        color: c.card,
        child: InkWell(
          onTap: () =>
              showItemEditor(context, ref, ItemKind.deal, existing: item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                IconTile(
                  icon: CupertinoIcons.person,
                  accent: Accents.sky,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: context.text.titleSmall!.copyWith(
                            decoration: item.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        Text(what, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (item.amount != null)
                  ExcludeSemantics(
                    child: Text(
                      money(item.amount),
                      style: context.text.titleSmall!.copyWith(
                        color: tone,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                CheckCircle(
                  done: item.done,
                  label: item.done
                      ? 'Mark ${item.title} as not settled'
                      : 'Mark ${item.title} as settled',
                  onChanged: (v) {
                    item.done = v;
                    ref.read(syncServiceProvider).save(item);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
