import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modules/module.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'common.dart';

String moduleHeroTag(LifeModule m) => 'module-icon-${m.id}';

/// Opens [m]: switches tab when it lives in the bottom nav, otherwise pushes
/// its page (with a hero flight from the tapped icon tile).
void openModule(BuildContext context, WidgetRef ref, LifeModule m) {
  HapticFeedback.selectionClick();
  ref.read(lastModuleProvider.notifier).state = m.id;
  final inNav = ref.read(appConfigProvider).navModules.any((n) => n.id == m.id);
  if (inNav) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    ref.read(currentTabProvider.notifier).state = m.id;
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ModulePage(module: m, pushed: true)),
    );
  }
}

/// The frame around every module: app bar with search and an "about" button,
/// the module's screen (or its intro the first time), and a + button.
class ModulePage extends ConsumerStatefulWidget {
  const ModulePage({super.key, required this.module, this.pushed = false});

  final LifeModule module;

  /// Pushed as a route (vs. living in a bottom-nav tab) — enables the hero.
  final bool pushed;

  @override
  ConsumerState<ModulePage> createState() => _ModulePageState();
}

class _ModulePageState extends ConsumerState<ModulePage> {
  bool _searchOpen = false;
  final _searchCtrl = TextEditingController();

  LifeModule get m => widget.module;
  String? get _searchKey => m.items.isEmpty ? null : m.items.first.kind;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchCtrl.clear();
    final key = _searchKey;
    if (key != null) ref.read(searchQueryProvider(key).notifier).state = '';
    setState(() => _searchOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final seen = ref.watch(introSeenProvider).contains(m.id);
    final key = _searchKey;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.pushed,
        title: _searchOpen && key != null
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search ${m.title.toLowerCase()}',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                onChanged: (v) =>
                    ref.read(searchQueryProvider(key).notifier).state = v,
              )
            : Text(m.title),
        actions: [
          if (seen && m.searchable && key != null)
            IconButton(
              tooltip: _searchOpen ? 'Close search' : 'Search ${m.title}',
              icon: Icon(
                _searchOpen ? CupertinoIcons.xmark : CupertinoIcons.search,
                size: 20,
              ),
              onPressed: () => _searchOpen
                  ? _closeSearch()
                  : setState(() => _searchOpen = true),
            ),
          if (seen)
            IconButton(
              tooltip: 'About ${m.title}',
              icon: const Icon(CupertinoIcons.info, size: 20),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ModuleIntroPage(module: m)),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        child: seen
            ? KeyedSubtree(
                key: const ValueKey('screen'),
                child: m.buildScreen(context),
              )
            : ModuleIntroView(
                key: const ValueKey('intro'),
                module: m,
                hero: widget.pushed,
                onExplore: () {
                  HapticFeedback.lightImpact();
                  ref.read(introSeenProvider.notifier).markSeen(m.id);
                },
              ),
      ),
      floatingActionButton: seen && m.items.isNotEmpty
          ? FloatingActionButton(
              heroTag: null,
              tooltip: 'Add ${m.items.first.singular.toLowerCase()}',
              onPressed: () {
                HapticFeedback.lightImpact();
                m.onAdd(context, ref);
              },
              child: const Icon(CupertinoIcons.add),
            )
          : null,
    );
  }
}

/// The intro page on its own route (from the ⓘ button).
class ModuleIntroPage extends StatelessWidget {
  const ModuleIntroPage({super.key, required this.module});
  final LifeModule module;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ModuleIntroView(
        module: module,
        onExplore: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// Big pastel icon tile, serif title, tagline, feature list and a pill CTA.
class ModuleIntroView extends StatelessWidget {
  const ModuleIntroView({
    super.key,
    required this.module,
    required this.onExplore,
    this.hero = false,
  });

  final LifeModule module;
  final VoidCallback onExplore;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final intro = module.intro;
    Widget tile = IconTile(icon: module.icon, accent: module.accent, size: 112);
    if (hero) tile = Hero(tag: moduleHeroTag(module), child: tile);
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
              children: [
                Center(child: ExcludeSemantics(child: tile)),
                const SizedBox(height: 22),
                Semantics(
                  header: true,
                  child: Text(
                    module.title,
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  intro.tagline,
                  textAlign: TextAlign.center,
                  style: context.text.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  intro.description,
                  textAlign: TextAlign.center,
                  style: context.text.bodyMedium!.copyWith(color: c.inkSub),
                ),
                const SizedBox(height: 26),
                for (final f in intro.features)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: MergeSemantics(
                      child: Row(
                        children: [
                          IconTile(icon: f.icon, accent: module.accent),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.title, style: context.text.titleSmall),
                                const SizedBox(height: 2),
                                Text(f.subtitle, style: context.text.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onExplore,
                child: Text('Explore ${module.title}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
