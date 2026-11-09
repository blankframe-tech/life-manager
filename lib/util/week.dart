import 'package:intl/intl.dart';

import '../models/item.dart';

final _dayMonth = DateFormat('d MMM');
final _day = DateFormat('d');
final _dayMonthYear = DateFormat('d MMM yyyy');

/// Midnight on the Monday of [d]'s week, in local time.
///
/// Constructed from y/m/d rather than by subtracting a [Duration] so it lands
/// on real local midnight even across a DST boundary, where a week is not
/// always 7×24h.
DateTime startOfWeek(DateTime d) {
  final local = d.toLocal();
  final midnight = DateTime(local.year, local.month, local.day);
  return midnight.subtract(Duration(days: midnight.weekday - DateTime.monday));
}

/// One week of transactions plus its totals — what the log groups by.
class WeekRollup {
  WeekRollup._(this.start, this.items, this.earned, this.spent);

  /// A week with nothing in it — so the current-week summary can render zeroes
  /// instead of disappearing on a week you haven't spent anything yet.
  WeekRollup.empty(this.start)
      : items = const [],
        earned = 0,
        spent = 0;

  /// Monday midnight, local.
  final DateTime start;

  /// The Sunday this week ends on.
  DateTime get end => DateTime(start.year, start.month, start.day + 6);

  /// Newest first, matching how the list renders them.
  final List<Item> items;

  /// Money in, as a positive number.
  final double earned;

  /// Money out, as a positive number.
  final double spent;

  double get net => earned - spent;

  /// Spending per category, largest first. Earnings are left out: mixing a
  /// salary into a "where did it go" breakdown would drown every other slice.
  Map<String, double> get spendByCategory {
    final totals = <String, double>{};
    for (final item in items) {
      if (item.isEarning) continue;
      final amount = item.amount ?? 0;
      if (amount == 0) continue;
      totals.update(item.category ?? 'Uncategorised', (v) => v + amount,
          ifAbsent: () => amount);
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in sorted) e.key: e.value};
  }
}

/// Groups [txns] into weeks, newest week first, with each week's rows sorted
/// newest first. Weeks with no transactions are simply absent — the log is a
/// list of what happened, not a calendar.
List<WeekRollup> rollupByWeek(Iterable<Item> txns) {
  final buckets = <DateTime, List<Item>>{};
  for (final item in txns) {
    buckets.putIfAbsent(startOfWeek(item.occurredAt), () => []).add(item);
  }
  final starts = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final start in starts)
      () {
        final items = buckets[start]!
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        var earned = 0.0;
        var spent = 0.0;
        for (final item in items) {
          if (item.isEarning) {
            earned += item.amount ?? 0;
          } else {
            spent += item.amount ?? 0;
          }
        }
        return WeekRollup._(start, items, earned, spent);
      }(),
  ];
}

/// "This week" / "Last week" / "4–10 Aug" — the heading above a week's rows.
/// Pass [now] to make the relative part testable.
String weekLabel(DateTime start, {DateTime? now}) {
  final current = startOfWeek(now ?? DateTime.now());
  final weeksAgo = current.difference(start).inDays ~/ 7;
  if (weeksAgo == 0) return 'This week';
  if (weeksAgo == 1) return 'Last week';
  return weekRangeLabel(start, now: now);
}

/// "4–10 Aug", or "28 Dec – 3 Jan" when the week straddles a month. The year
/// is appended unless the whole week sits in the current one — a week that
/// starts in December and ends in January is last year's, and saying so is the
/// difference between "29 Dec – 4 Jan" and a date you can actually place.
String weekRangeLabel(DateTime start, {DateTime? now}) {
  final end = DateTime(start.year, start.month, start.day + 6);
  final thisYear = (now ?? DateTime.now()).year;
  final showYear = start.year != thisYear || end.year != thisYear;
  final tail = showYear ? _dayMonthYear.format(end) : _dayMonth.format(end);
  return start.month == end.month
      ? '${_day.format(start)}–$tail'
      : '${_dayMonth.format(start)} – $tail';
}
