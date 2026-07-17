import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0', 'en_US');
final _dayMonth = DateFormat('d MMM');

/// "৳2,000". Whole-taka only (the source figures are whole numbers).
String money(num? v) => v == null ? '' : '৳${_money.format(v)}';

/// Compact form used in dense chips: 33000 -> "33k", 500 -> "500".
String moneyK(num? v) {
  if (v == null) return '';
  if (v >= 1000 && v % 100 == 0) {
    final k = v / 1000;
    final s = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
    return '৳${s}k';
  }
  return money(v);
}

String shortDate(DateTime d) => _dayMonth.format(d);

/// Parses a leading money token like "10k", "33k", "800", "1.5k" from a line.
/// Returns null if no clear leading amount is present. Used only to feed the
/// budget/dealings totals — the original wording is always kept verbatim.
double? parseLeadingAmount(String text) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*[kK]\b').firstMatch(text);
  if (m != null) return double.parse(m.group(1)!) * 1000;
  final n = RegExp(r'\b(\d{3,})\b').firstMatch(text);
  if (n != null) return double.parse(n.group(1)!);
  return null;
}
