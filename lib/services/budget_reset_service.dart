import 'package:isar_community/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/history_event.dart';
import '../models/item.dart';

const _kNeedsResetMonthKey = 'needs_reset_month';

/// Un-ticks every checked-off Needs item once per calendar month. Run at
/// startup (see `main.dart`) — cheap no-op on every launch except the first
/// one in a new month, tracked via a "YYYY-MM" marker in SharedPreferences.
///
/// Writes go straight to Isar (not through `SyncService.save`) since this
/// runs before the widget tree — and therefore before `SyncService` — exists.
/// Each reset item is still flagged `isSynced = false` and gets an
/// `uncompleted` [HistoryEvent], so the reset itself syncs out and shows up
/// in Activity History like any other completion toggle.
Future<void> resetNeedsIfNewMonth(Isar isar, SharedPreferences prefs) async {
  final now = DateTime.now();
  final monthKey =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';
  if (prefs.getString(_kNeedsResetMonthKey) == monthKey) return;

  final done = await isar.items
      .filter()
      .kindEqualTo(ItemKind.budget)
      .categoryEqualTo(BudgetCategory.needs)
      .doneEqualTo(true)
      .findAll();

  if (done.isNotEmpty) {
    final nowUtc = DateTime.now().toUtc();
    await isar.writeTxn(() async {
      for (final item in done) {
        item.done = false;
        item.updatedAt = nowUtc;
        item.isSynced = false;
        await isar.items.put(item);
        await isar.historyEvents.put(HistoryEvent()
          ..uuid = const Uuid().v4()
          ..itemUuid = item.uuid
          ..itemKind = item.kind
          ..title = item.title
          ..action = HistoryAction.uncompleted
          ..timestamp = nowUtc
          ..isSynced = false);
      }
    });
  }

  await prefs.setString(_kNeedsResetMonthKey, monthKey);
}
