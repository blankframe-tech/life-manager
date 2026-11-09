import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/leaf_mark.dart';

/// Shows [child] once onboarding is done; the four-page welcome before that.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final done = ref.watch(onboardingDoneProvider);
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 450),
      child: done
          ? KeyedSubtree(key: const ValueKey('app'), child: child)
          : const OnboardingScreen(key: ValueKey('onboarding')),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  int _page = 0;
  static const _count = 4;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_page < _count - 1) {
      _pages.nextPage(
        duration: MediaQuery.of(context).disableAnimations
            ? const Duration(milliseconds: 1)
            : const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _finish() {
    if (_name.text.trim().isNotEmpty) {
      ref.read(userNameProvider.notifier).set(_name.text);
    }
    ref.read(onboardingDoneProvider.notifier).complete();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final modules = ref.watch(appConfigProvider).modules;
    return Scaffold(
      body: Stack(
        children: [
          // Decorative soft shapes, as in the mock.
          Positioned(
            left: -120,
            bottom: -60,
            child: _blob(context, 380, Accents.sage.softOf(context)),
          ),
          Positioned(
            right: -80,
            bottom: -140,
            child: _blob(context, 320, Accents.sage.softOf(context)),
          ),
          Positioned(
            right: 18,
            bottom: 230,
            child: _blob(
              context,
              104,
              Accents.butter.chart.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.55
                    : 0.9,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedOpacity(
                    opacity: _page < _count - 1 ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _page < _count - 1 ? _finish : null,
                      child: const Text('Skip'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    onPageChanged: (p) => setState(() => _page = p),
                    children: [
                      _page1(context),
                      _modulesPage(context, modules),
                      _privacyPage(context),
                      _namePage(context),
                    ],
                  ),
                ),
                Semantics(
                  label: 'Page ${_page + 1} of $_count',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _count; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _page ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page
                                ? c.primary
                                : c.inkSub.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                      ),
                      child: Text(
                        _page == 0
                            ? 'Get Started'
                            : _page == _count - 1
                            ? 'Start using Life Manager'
                            : 'Continue',
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Your data stays private. Always.',
                    style: context.text.bodySmall!.copyWith(
                      color: c.ink.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(BuildContext context, double size, Color color) =>
      ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );

  Widget _pageFrame({required List<Widget> children}) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
    child: Column(children: children),
  );

  Widget _page1(BuildContext context) => _pageFrame(
    children: [
      const SizedBox(height: 40),
      const LeafMark(size: 104),
      const SizedBox(height: 72),
      Semantics(
        header: true,
        child: Text(
          'Take control.\nLive better.',
          textAlign: TextAlign.center,
          style: context.text.displaySmall!.copyWith(
            color: context.colors.primary,
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'Organize your money, tasks, and life in one beautiful place.',
        textAlign: TextAlign.center,
        style: context.text.bodyLarge,
      ),
    ],
  );

  Widget _modulesPage(BuildContext context, List modules) => _pageFrame(
    children: [
      Semantics(
        header: true,
        child: Text(
          'Everything in\none place',
          textAlign: TextAlign.center,
          style: context.text.displaySmall,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Pick up any part of your life in a tap.',
        textAlign: TextAlign.center,
        style: context.text.bodyLarge,
      ),
      const SizedBox(height: 28),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 16,
        children: [
          for (final m in modules)
            SizedBox(
              width: 84,
              child: MergeSemantics(
                child: Column(
                  children: [
                    IconTile(icon: m.icon, accent: m.accent, size: 60),
                    const SizedBox(height: 6),
                    Text(
                      m.title,
                      textAlign: TextAlign.center,
                      style: context.text.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _privacyPage(BuildContext context) => _pageFrame(
    children: [
      const SizedBox(height: 20),
      const IconTile(
        icon: CupertinoIcons.lock_shield,
        accent: Accents.sage,
        size: 112,
      ),
      const SizedBox(height: 36),
      Semantics(
        header: true,
        child: Text(
          'Private by\ndesign',
          textAlign: TextAlign.center,
          style: context.text.displaySmall,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        'Everything lives on this phone. No account, no cloud, no tracking. '
        'Export a backup whenever you like, and lock the app with Face ID.',
        textAlign: TextAlign.center,
        style: context.text.bodyLarge,
      ),
    ],
  );

  Widget _namePage(BuildContext context) => _pageFrame(
    children: [
      const SizedBox(height: 20),
      const IconTile(
        icon: CupertinoIcons.hand_raised,
        accent: Accents.butter,
        size: 112,
      ),
      const SizedBox(height: 36),
      Semantics(
        header: true,
        child: Text(
          'What should\nwe call you?',
          textAlign: TextAlign.center,
          style: context.text.displaySmall,
        ),
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _name,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _finish(),
        decoration: const InputDecoration(
          hintText: 'Your first name (optional)',
        ),
      ),
    ],
  );
}
