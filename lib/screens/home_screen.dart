import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/module.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';
import '../widgets/module_nav.dart';
import 'settings_screen.dart';

/// "Good morning" / "Good afternoon" / "Good evening" for [now].
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Good morning';
  if (h >= 12 && h < 17) return 'Good afternoon';
  return 'Good evening';
}

String _emojiFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return '🌿';
  if (h >= 12 && h < 17) return '☀️';
  return '🌙';
}

/// Home: greeting, quick module tiles, then each module's summary card in
/// config order.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final name = ref.watch(userNameProvider);
    final now = DateTime.now();
    final greeting = '${greetingFor(now)}${name.isEmpty ? '' : ', $name'}';
    final cards = [for (final m in config.modules) ?m.buildHomeCard(context)];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  const LeafMarkSmall(),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(CupertinoIcons.gear, size: 22),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
              child: Semantics(
                header: true,
                label: greeting,
                excludeSemantics: true,
                child: Text(
                  '$greeting ${_emojiFor(now)}',
                  style: context.text.headlineMedium,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
              child: Text(
                "Here's your overview for today.",
                style: context.text.bodyLarge!.copyWith(
                  color: context.colors.inkSub,
                ),
              ),
            ),
            _QuickTiles(modules: config.modules),
            const SizedBox(height: 14),
            if (cards.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: emptyState(
                  CupertinoIcons.leaf_arrow_circlepath,
                  'A quiet day',
                  'Open a module above to get started.',
                ),
              ),
            for (var i = 0; i < cards.length; i++)
              _FadeIn(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: cards[i],
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: config.modules.any((m) => m.items.isNotEmpty)
          ? FloatingActionButton(
              heroTag: null,
              tooltip: 'Quick add',
              onPressed: () {
                HapticFeedback.lightImpact();
                _quickAdd(context, ref, config.modules);
              },
              child: const Icon(CupertinoIcons.add),
            )
          : null,
    );
  }

  void _quickAdd(
    BuildContext context,
    WidgetRef ref,
    List<LifeModule> modules,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheet).size.height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Add something', style: sheet.text.headlineSmall),
              ),
              for (final m in modules)
                if (m.items.isNotEmpty)
                  ListTile(
                    leading: IconTile(icon: m.icon, accent: m.accent, size: 40),
                    title: Text('New ${m.items.first.singular.toLowerCase()}'),
                    subtitle: Text(m.title),
                    onTap: () {
                      Navigator.of(sheet).pop();
                      showItemEditor(context, ref, m.items.first.kind);
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class LeafMarkSmall extends StatelessWidget {
  const LeafMarkSmall({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'Life Manager',
    style: context.text.labelMedium!.copyWith(letterSpacing: 0.4),
  );
}

/// The row of module tiles under the greeting. The first four modules, then
/// "More" when there are others.
class _QuickTiles extends ConsumerWidget {
  const _QuickTiles({required this.modules});
  final List<LifeModule> modules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (modules.isEmpty) return const SizedBox.shrink();
    final shown = modules.take(4).toList();
    final active = ref.watch(lastModuleProvider) ?? modules.first.id;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: cardDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in shown)
            Expanded(
              child: _Tile(
                label: m.title,
                onTap: () => openModule(context, ref, m),
                tile: Hero(
                  tag: moduleHeroTag(m),
                  child: IconTile(
                    icon: m.icon,
                    accent: m.accent,
                    size: 54,
                    filled: m.id == active,
                  ),
                ),
                selected: m.id == active,
              ),
            ),
          if (modules.length > 4)
            Expanded(
              child: _Tile(
                label: 'More',
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(currentTabProvider.notifier).state = 'more';
                },
                tile: const IconTile(
                  icon: CupertinoIcons.ellipsis,
                  accent: Accents.forest,
                  size: 54,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.onTap,
    required this.tile,
    this.selected = false,
  });
  final String label;
  final VoidCallback onTap;
  final Widget tile;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              tile,
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelMedium!.copyWith(
                  color: selected ? context.colors.ink : null,
                  fontWeight: selected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Staggered fade + rise for home cards (skipped under reduce-motion).
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
