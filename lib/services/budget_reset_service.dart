import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/history_event.dart';
import '../models/item.dart';
import '../store/local_store.dart';

const _kNeedsResetMonthKey = 'needs_reset_month';

/// Un-ticks every checked-off Needs item once per calendar month. Run at
/// startup (see `main.dart`) — cheap no-op on every launch except the first
/// one in a new month, tracked via a "YYYY-MM" marker in SharedPreferences.
///
/// Writes go straight to the store (not through `SyncService.save`) since this
/// runs before the widget tree — and therefore before `SyncService` — exists.
/// Each reset item is still flagged `isSynced = false` and gets an
/// `uncompleted` [HistoryEvent], so the reset itself syncs out and shows up
/// in Activity History like any other completion toggle.
Future<void> resetNeedsIfNewMonth(
  LocalStore store,
  SharedPreferences prefs,
) async {
  final now = DateTime.now();
  final monthKey =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';
  if (prefs.getString(_kNeedsResetMonthKey) == monthKey) return;

  final done = [
    for (final i in await store.items())
      if (i.kind == ItemKind.budget &&
          i.category == BudgetCategory.needs &&
          i.done)
        i,
  ];

  if (done.isNotEmpty) {
    final nowUtc = DateTime.now().toUtc();
    for (final item in done) {
      item.done = false;
      item.updatedAt = nowUtc;
      item.isSynced = false;
    }
    await store.putItems(done);
    await store.putHistory([
      for (final item in done)
        HistoryEvent()
          ..uuid = const Uuid().v4()
          ..itemUuid = item.uuid
          ..itemKind = item.kind
          ..title = item.title
          ..action = HistoryAction.uncompleted
          ..timestamp = nowUtc
          ..isSynced = false,
    ]);
  }

  await prefs.setString(_kNeedsResetMonthKey, monthKey);
}
