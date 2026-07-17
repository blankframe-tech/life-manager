import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// Small uppercase group header, iOS grouped-list style.
Widget groupHeader(String text, {String? trailing}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: AppColors.inkSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              color: AppColors.inkSub,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    ),
  );
}

/// Centered friendly empty state.
Widget emptyState(IconData icon, String title, String subtitle) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 54, color: AppColors.hair),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.ink)),
        const SizedBox(height: 6),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.inkSub)),
      ],
    ),
  );
}

/// Wraps a row with swipe-to-delete (soft delete via the sync engine).
class DeletableRow extends ConsumerWidget {
  const DeletableRow({super.key, required this.item, required this.child});
  final Item item;
  final Widget child;

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
      onDismissed: (_) => ref.read(syncServiceProvider).delete(item),
      child: child,
    );
  }
}

/// A rounded card wrapper for a group of rows.
Widget cardGroup(List<Widget> children) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: cardDecoration(),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

/// A thin inset separator between rows in a card group.
Widget rowDivider() => const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 1, thickness: 0.5, color: AppColors.hair),
    );
