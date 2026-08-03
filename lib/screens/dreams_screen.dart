import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../widgets/common.dart';
import '../widgets/item_editor.dart';

/// Big long-term wishes — no dates, no pressure.
class DreamsScreen extends ConsumerWidget {
  const DreamsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(itemsProvider(ItemKind.dream));
    final query = ref.watch(searchQueryProvider(ItemKind.dream));
    return async.when(
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
        children: const [LoadingSkeleton()],
      ),
      error: (e, _) =>
          errorState(context, () => ref.invalidate(itemsProvider(ItemKind.dream))),
      data: (all) {
        final items = filterBySearch(all, query);
        if (items.isEmpty) {
          return emptyState(
            CupertinoIcons.sparkles,
            'No dreams yet',
            'Big things for the future — jot them down.',
            onAction: () => showItemEditor(context, ref, ItemKind.dream),
            actionLabel: 'Add a dream',
          );
        }
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DeletableRow(
                  item: item,
                  semanticLabel: item.title,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => showItemEditor(context, ref, ItemKind.dream,
                          existing: item),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.sparkles,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
