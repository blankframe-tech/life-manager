import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Small uppercase group header, iOS grouped-list style.
Widget groupHeader(BuildContext context, String text, {String? trailing}) {
  final c = context.colors;
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              color: c.inkSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: TextStyle(
              color: c.inkSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    ),
  );
}

/// Centered friendly empty state. Pass [onAction]/[actionLabel] to surface a
/// CTA — the moment a list is empty is exactly when "add" should be obvious.
Widget emptyState(
  IconData icon,
  String title,
  String subtitle, {
  VoidCallback? onAction,
  String? actionLabel,
}) {
  return Builder(builder: (context) {
    final c = context.colors;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 54, color: c.hair),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.inkSub)),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  });
}

/// Shimmer-free pulsing placeholder shaped like a [cardGroup] of rows —
/// shown only on first load (Isar reads after that are effectively instant).
class LoadingSkeleton extends StatefulWidget {
  const LoadingSkeleton({super.key, this.rows = 3});
  final int rows;

  @override
  State<LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 0.75; // static, still-visible placeholder — no pulsing
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.hair;
    return FadeTransition(
      opacity: _c.drive(Tween(begin: 0.5, end: 1)),
      child: cardGroup(context, [
        for (var i = 0; i < widget.rows; i++) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                        color: base, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 14,
                  decoration: BoxDecoration(
                      color: base, borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
          ),
          if (i != widget.rows - 1) rowDivider(context),
        ],
      ]),
    );
  }
}

/// Human error state with a retry action — never show a raw exception string.
Widget errorState(BuildContext context, VoidCallback onRetry) {
  final c = context.colors;
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(CupertinoIcons.exclamationmark_triangle, size: 44, color: c.inkSub),
        const SizedBox(height: 14),
        Text('Something went wrong',
            style:
                TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
        const SizedBox(height: 6),
        Text('Pull to retry, or tap below.',
            style: TextStyle(fontSize: 14, color: c.inkSub)),
        const SizedBox(height: 14),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

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
    return Dismissible(
      key: ValueKey(item.uuid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AppColors.rose,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(CupertinoIcons.delete, color: Colors.white),
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
      child: Semantics(label: semanticLabel, container: true, child: child),
    );
  }
}

/// A rounded card wrapper for a group of rows.
Widget cardGroup(BuildContext context, List<Widget> children) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: cardDecoration(context),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

/// A thin inset separator between rows in a card group.
Widget rowDivider(BuildContext context) => Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Divider(height: 1, thickness: 0.5, color: context.colors.hair),
    );
