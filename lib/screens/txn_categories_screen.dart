import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../services/txn_category_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/new_category_dialog.dart';

/// Add and remove the categories the Transactions screen tags entries with.
///
/// Removing one never touches data: transactions store the category as text,
/// so the ones already tagged keep their label (and keep counting towards that
/// slice of the weekly rollup) — the name just stops being offered for new
/// entries, and can be added back at any time.
class TxnCategoriesScreen extends ConsumerWidget {
  const TxnCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final configured = ref.watch(txnCategoriesProvider);
    final txns = ref.watch(itemsProvider(ItemKind.txn)).valueOrNull ?? const [];

    final counts = <String, int>{};
    for (final item in txns) {
      final name = item.category;
      if (name != null && name.isNotEmpty) {
        counts.update(name, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    // Strays (removed here, or created on another device) are listed too, so a
    // category you can see in the log is always manageable from this screen.
    final categories = mergeUsedCategories(configured, counts.keys);

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          groupHeader(context, 'Transaction categories'),
          cardGroup(context, [
            for (var i = 0; i < categories.length; i++) ...[
              _row(context, ref, categories[i], counts[categories[i]] ?? 0,
                  configured: configured.contains(categories[i])),
              rowDivider(context),
            ],
            _addTile(context, ref),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Removing a category keeps every transaction already tagged with '
              'it — the name just stops being offered for new ones.',
              style: TextStyle(fontSize: 12, color: c.inkSub),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, String name, int uses,
      {required bool configured}) {
    final c = context.colors;
    return ListTile(
      leading: Container(
        width: 12,
        height: 12,
        decoration:
            BoxDecoration(color: categoryColor(name), shape: BoxShape.circle),
      ),
      title: Text(name),
      subtitle: Text(
        [
          uses == 0
              ? 'Not used yet'
              : '$uses transaction${uses == 1 ? '' : 's'}',
          if (!configured) 'removed — still tagging the above',
        ].join(' · '),
        style: TextStyle(fontSize: 12, color: c.inkSub),
      ),
      trailing: configured
          ? IconButton(
              tooltip: 'Remove $name',
              icon: const Icon(CupertinoIcons.minus_circle,
                  color: AppColors.rose, size: 20),
              onPressed: () => _remove(context, ref, name, uses),
            )
          : TextButton(
              onPressed: () =>
                  ref.read(txnCategoriesProvider.notifier).add(name),
              child: const Text('Restore'),
            ),
    );
  }

  Widget _addTile(BuildContext context, WidgetRef ref) {
    return Material(
      color: context.colors.card,
      child: InkWell(
        onTap: () => _promptAdd(context, ref),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(CupertinoIcons.add_circled, size: 20, color: AppColors.sky),
              SizedBox(width: 10),
              Text('Add a category',
                  style: TextStyle(
                      color: AppColors.sky,
                      fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, String name, int uses) async {
    if (uses > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Remove "$name"?'),
          content: Text(
            '$uses transaction${uses == 1 ? '' : 's'} still use this category. '
            'They keep the label and stay in your weekly totals — it just '
            "won't be offered for new transactions.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove',
                  style: TextStyle(color: AppColors.rose)),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final notifier = ref.read(txnCategoriesProvider.notifier);
    notifier.remove(name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "$name"'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          // Re-adding appends rather than restoring the old position — a
          // trade worth making to keep the store a plain ordered list.
          onPressed: () => notifier.add(name),
        ),
      ),
    );
  }

  Future<void> _promptAdd(BuildContext context, WidgetRef ref) async {
    final name = await promptForCategory(context);
    final clean = name?.trim() ?? '';
    if (clean.isEmpty || !context.mounted) return;
    if (ref.read(txnCategoriesProvider.notifier).add(clean) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$clean" is already a category')),
      );
    }
  }
}
