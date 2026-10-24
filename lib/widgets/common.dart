import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Section header above a card.
Widget groupHeader(BuildContext context, String text, {String? trailing}) {
  final c = context.colors;
  final style = context.text.labelMedium!.copyWith(
    color: c.inkSub,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  return Padding(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
    child: Semantics(
      header: true,
      child: Row(
        children: [
          Expanded(child: Text(text, style: style)),
          if (trailing != null) Text(trailing, style: style),
        ],
      ),
    ),
  );
}

/// A rounded square tile with a pastel background and an icon — the mock's
/// signature element (module tiles, row leaders, intro features).
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.accent,
    this.size = 44,
    this.filled = false,
  });

  final IconData icon;
  final ModuleAccent accent;
  final double size;

  /// Solid primary fill (the "active" quick tile).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? c.primary : accent.softOf(context),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        icon,
        size: size * 0.48,
        color: filled ? c.onPrimary : accent.inkOf(context),
      ),
    );
  }
}

/// Centered, encouraging empty state: a soft circle with the icon, a serif
/// title, and an optional CTA — the moment a list is empty is exactly when
/// "add" should be obvious.
Widget emptyState(
  IconData icon,
  String title,
  String subtitle, {
  VoidCallback? onAction,
  String? actionLabel,
  ModuleAccent accent = Accents.sage,
}) {
  return Builder(
    builder: (context) {
      final c = context.colors;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: accent.softOf(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 40, color: accent.inkOf(context)),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium!.copyWith(color: c.inkSub),
              ),
              if (onAction != null && actionLabel != null) ...[
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(CupertinoIcons.add, size: 18),
                  label: Text(actionLabel),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// Human error state with a retry action — never show a raw exception string.
Widget errorState(BuildContext context, VoidCallback onRetry) {
  final c = context.colors;
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          CupertinoIcons.exclamationmark_triangle,
          size: 44,
          color: c.inkSub,
        ),
        const SizedBox(height: 14),
        Text('Something went wrong', style: context.text.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Your data is safe. Try again.',
          style: context.text.bodyMedium!.copyWith(color: c.inkSub),
        ),
        const SizedBox(height: 14),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

/// Data is local (Isar), so the first frame is effectively instant — the
/// loading branch renders nothing rather than flashing a skeleton.
Widget instantLoading() => const SizedBox.shrink();

/// Wraps a row with swipe-to-delete (soft delete via the sync engine), with
/// an Undo affordance since the swipe itself is irreversible-feeling.
class DeletableRow extends ConsumerWidget {
  const DeletableRow({
    super.key,
    required this.item,
    required this.child,
    this.semanticLabel,
  });
  final Item item;
  final Widget child;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Dismissible(
      key: ValueKey(item.uuid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: c.negative,
        child: Icon(CupertinoIcons.delete, color: c.bg),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        final sync = ref.read(syncServiceProvider);
        final title = item.title;
        sync.delete(item);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "$title"'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                item.isDeleted = false;
                sync.save(item);
              },
            ),
          ),
        );
      },
      child: Semantics(
        label: semanticLabel,
        hint: 'Swipe left to delete',
        container: true,
        child: child,
      ),
    );
  }
}

/// A 44pt circular check toggle with haptics and an animated fill.
class CheckCircle extends StatelessWidget {
  const CheckCircle({
    super.key,
    required this.done,
    required this.onChanged,
    required this.label,
    this.color,
  });

  final bool done;
  final ValueChanged<bool> onChanged;

  /// What toggling does, for VoiceOver ("Mark Rent as paid").
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = color ?? c.primary;
    void toggle() {
      HapticFeedback.selectionClick();
      onChanged(!done);
    }

    // Own node with its own tap action, so it isn't merged into the row.
    return Semantics(
      container: true,
      label: label,
      checked: done,
      button: true,
      onTap: toggle,
      excludeSemantics: true,
      child: InkResponse(
        radius: 24,
        onTap: toggle,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? fill : Colors.transparent,
                border: Border.all(color: done ? fill : c.inkSub, width: 1.6),
              ),
              child: done
                  ? Icon(CupertinoIcons.checkmark, size: 14, color: c.bg)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A card with a title row and optional "View all" action — the home and
/// budget building block.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.onViewAll,
    this.childPadding = const EdgeInsets.fromLTRB(18, 0, 18, 16),
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onViewAll;

  /// Padding around [child]; rows that bring their own insets pass less.
  final EdgeInsets childPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: cardDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: context.text.titleMedium),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
          Padding(padding: childPadding, child: child),
          // Bottom-left, not in the title row: the FAB floats bottom-right and
          // covered a top-right link on whichever card scrolled beneath it.
          if (onViewAll != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onViewAll,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Semantics(
                    label: 'View all $title',
                    excludeSemantics: true,
                    child: const Text('View all'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded card wrapper for a group of rows.
Widget cardGroup(BuildContext context, List<Widget> children) {
  final c = context.colors;
  // Material (not a coloured DecoratedBox) so ListTile ink shows through.
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: cardDecoration(context).boxShadow,
    ),
    child: Material(
      color: c.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: c.hair),
      ),
      child: Column(children: children),
    ),
  );
}

/// A thin inset separator between rows in a card group.
Widget rowDivider(BuildContext context) => Padding(
  padding: const EdgeInsets.only(left: 16),
  child: Divider(height: 1, thickness: 1, color: context.colors.hair),
);

/// Rounded progress bar; clamps to [0, 1].
class SoftBar extends StatelessWidget {
  const SoftBar({
    super.key,
    required this.value,
    required this.color,
    this.track,
  });
  final double value;
  final Color color;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.isNaN ? 0 : value.clamp(0.0, 1.0)),
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: 6,
          color: color,
          backgroundColor: track ?? context.colors.hair,
        ),
      ),
    );
  }
}
