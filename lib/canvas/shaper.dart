// The shaper: reads what the user already keeps (a Google Keep note, a
// WhatsApp chat with themselves, a budget sheet saved as CSV) and compiles it
// into canvas sections and the rows that fill them. Offline, deterministic,
// no model. See docs/CANVAS.md for the rules.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../models/item.dart';
import 'blueprint.dart';

/// One thing the user brought in.
class SourceDoc {
  const SourceDoc(this.name, this.text);
  final String name;
  final String text;
}

/// A compiled [SourceDoc]. Only [hash], [name] and [sections] are saved; the
/// [items] are written to the database once and never kept here.
class CompiledSource {
  const CompiledSource({
    required this.hash,
    required this.name,
    required this.sections,
    this.items = const [],
  });
  final String hash;
  final String name;
  final List<SectionSpec> sections;
  final List<Item> items;

  Map<String, Object> toJson() => {
    'hash': hash,
    'name': name,
    'sections': [for (final s in sections) s.toJson()],
  };

  static CompiledSource? fromJson(Object? j) {
    if (j is! Map) return null;
    final hash = j['hash'], name = j['name'], sections = j['sections'];
    if (hash is! String || name is! String || sections is! List) return null;
    return CompiledSource(
      hash: hash,
      name: name,
      sections: [for (final s in sections) ?SectionSpec.fromJson(s)],
    );
  }
}

/// Inputs larger than this are cut, so a wrong file can't stall the phone.
const kMaxSourceChars = 200000;
const _maxItemsPerSource = 600;

/// Each source gets this many order slots, so sections keep the order in
/// which sources were added.
const kOrderStride = 1000;

class Shaper {
  /// Bump when the rules change in a way that should re-shape old imports.
  static const version = 1;

  /// Content fingerprint: the same text (any line endings, any trailing
  /// space) always gives the same hash, so a re-import is recognised.
  static String hashOf(String text) =>
      sha256.convert(utf8.encode(_normalize(text))).toString().substring(0, 16);

  /// Compiles one source. [orderBase] places its sections after the ones the
  /// canvas already has. [now] is injectable for tests ("tomorrow").
  static CompiledSource compile(
    SourceDoc doc, {
    int orderBase = 0,
    DateTime? now,
  }) {
    final text = _normalize(doc.text);
    final hash = hashOf(doc.text);
    final ctx = _Ctx(
      hash: hash,
      sourceName: _sourceTitle(doc.name),
      orderBase: orderBase,
      now: now ?? DateTime.now(),
    );
    final blocks =
        _looksLikeTable(text, doc.name) ?? _blocks(text, ctx.sourceName);
    for (final b in blocks) {
      ctx.emit(b);
    }
    return CompiledSource(
      hash: hash,
      name: ctx.sourceName,
      sections: ctx.sections,
      items: ctx.items,
    );
  }

  /// A row typed into a section's "Add" field, parsed with the same rules.
  static Item quickItem(String line, SectionSpec section, {DateTime? now}) {
    final l = _Line.parse(line, now ?? DateTime.now());
    final item = _itemFor(section.kind, l, section.title, now ?? DateTime.now())
      ..uuid = const Uuid().v4()
      ..section = section.id
      ..sortOrder = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return item;
  }

  /// Where a line typed into "Jot anything" belongs: the first of
  /// [sections] whose kind matches what the line looks like, else the first
  /// checklist, else the first section. Null only when [sections] is empty.
  static SectionSpec? route(String line, List<SectionSpec> sections) {
    if (sections.isEmpty) return null;
    final l = _Line.parse(line, DateTime.now());
    final want = <String>[
      if (l.owe != null) ItemKind.deal,
      if (_hasKeyword(l.text, _Cat.shopping)) ItemKind.buy,
      if (l.amount != null) ...[ItemKind.txn, ItemKind.budget, ItemKind.buy],
      if (_hasKeyword(l.text, _Cat.goals)) ItemKind.dream,
      ItemKind.task,
      ItemKind.buy,
    ];
    for (final k in want) {
      for (final s in sections) {
        if (s.kind == k) return s;
      }
    }
    return sections.first;
  }
}

// ── Text normalisation ──────────────────────────────────────────────────────

const _bnDigits = '০১২৩৪৫৬৭৮৯';

String _normalize(String raw) {
  var s = raw.length > kMaxSourceChars
      ? raw.substring(0, kMaxSourceChars)
      : raw;
  s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // Bangla digits → ASCII, so ৳১৫০০ reads as 1500.
  final b = StringBuffer();
  for (final ch in s.runes) {
    final i = _bnDigits.indexOf(String.fromCharCode(ch));
    b.write(i >= 0 ? '$i' : String.fromCharCode(ch));
  }
  return b.toString().split('\n').map((l) => l.trimRight()).join('\n').trim();
}

String _sourceTitle(String name) {
  final base = name.split(RegExp(r'[/\\]')).last.trim();
  final noExt = base.replaceFirst(
    RegExp(r'\.(txt|md|csv|tsv)$', caseSensitive: false),
    '',
  );
  final t = noExt.replaceAll(RegExp(r'[_]+'), ' ').trim();
  return t.isEmpty ? 'My notes' : t;
}

// WhatsApp exports: "[12/10/26, 9:41:03 PM] Name: text" (iOS) and
// "12/10/26, 9:41 pm - Name: text" (Android).
final _chatPrefix = RegExp(
  r'^\[?(\d{1,2})[/.](\d{1,2})[/.](\d{2,4}),?\s+\d{1,2}:\d{2}(?::\d{2})?\s*(?:[aApP]\.?\s?[mM]\.?)?\]?\s*(?:-\s*)?[^:]{1,40}:\s*',
);

final _chatNoise = RegExp(
  r'end-to-end encrypted|<media omitted>|this message was deleted|you deleted this message',
  caseSensitive: false,
);

// ── Keywords ────────────────────────────────────────────────────────────────

enum _Cat { people, spend, budget, shopping, goals, todo, notes }

const _keywords = {
  _Cat.people: [
    'owe', 'owes', 'dena', 'paona', 'pabo', 'loan', 'loans', 'lent', //
    'borrow', 'borrowed', 'debt', 'debts', 'dealing', 'dealings', 'hisab',
    'hishab', 'udhar', 'receivable', 'payable', 'dues',
  ],
  _Cat.spend: [
    'expense', 'expenses', 'spent', 'spending', 'spend', 'khoroch', //
    'kharach', 'transaction', 'transactions', 'log',
  ],
  _Cat.budget: [
    'budget', 'bill', 'bills', 'monthly', 'salary', 'finance', 'finances', //
    'financial', 'money', 'saving', 'savings', 'fixed cost', 'cost', 'costs',
  ],
  _Cat.shopping: [
    'bazaar', 'bazar', 'grocery', 'groceries', 'shopping', 'buy', 'market', //
    'kenakata', 'kinbo', 'cart', 'wishlist', 'to buy',
  ],
  _Cat.goals: [
    'dream', 'dreams', 'goal', 'goals', 'someday', 'bucket', 'wish', //
    'wishes', 'vision', 'future', 'resolution', 'resolutions', 'one day',
  ],
  _Cat.todo: [
    'todo', 'to-do', 'to do', 'task', 'tasks', 'kaj', 'chore', 'chores', //
    'errand', 'errands', 'pending', 'work', 'office', 'reminder', 'reminders',
  ],
  _Cat.notes: [
    'note', 'notes', 'idea', 'ideas', 'journal', 'diary', 'thought', //
    'thoughts', 'info', 'details', 'misc', 'random', 'quote', 'quotes',
    'recipe', 'recipes', 'reflection',
  ],
};

final _wordRe = RegExp(r"[a-z][a-z'\-]*");

bool _hasKeyword(String text, _Cat cat) => _keywordHits(text, cat) > 0;

int _keywordHits(String text, _Cat cat) {
  final lower = text.toLowerCase();
  final words = _wordRe.allMatches(lower).map((m) => m.group(0)!).toSet();
  var n = 0;
  for (final k in _keywords[cat]!) {
    if (k.contains(' ') ? lower.contains(k) : words.contains(k)) n++;
  }
  return n;
}

/// The strongest keyword category in a heading, if any. Ties go to the
/// earlier category in [_Cat] (people before money before lists).
_Cat? _headingCat(String heading) {
  _Cat? best;
  var bestHits = 0;
  for (final c in _Cat.values) {
    final h = _keywordHits(heading, c);
    if (h > bestHits) {
      best = c;
      bestHits = h;
    }
  }
  return best;
}

// ── Lines ───────────────────────────────────────────────────────────────────

final _bulletRe = RegExp(
  r'^\s*(?:(?:[-*•▪◦·–+]|\d{1,2}[.)])\s+)?(?:\[( |x|X|✓)\]\s*|([☐☑✓✔✅❌])\s*)?',
);
bool _isBullet(String s) => (_bulletRe.firstMatch(s)?.end ?? 0) > 0;

final _strikeRe = RegExp(r'^~~(.+)~~$');

final _moneyPrefix = RegExp(
  r'(?:৳|\btk\.?|\btaka\b|\bbdt\b|\$|\brs\.?)\s*(\d[\d,]*(?:\.\d+)?)\s*(k|lakh|lac|lakhs)?\b',
  caseSensitive: false,
);
final _moneySuffix = RegExp(
  r'(\d[\d,]*(?:\.\d+)?)\s*(k|lakh|lac|lakhs|tk\.?|taka|৳|bdt|/-)(?![a-z])',
  caseSensitive: false,
);
final _moneyTrailing = RegExp(r'(?:^|[\s:=\-–])(\d[\d,]*(?:\.\d+)?)\s*$');
final _anyNumber = RegExp(r'\b(\d[\d,]*(?:\.\d+)?)\b');

const _months = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];
const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

// Whole month / weekday words only, so "market" and "wedding" stay words.
const _month =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?';
const _lead = r'\b(?:by\s+|on\s+|due\s+|before\s+)?';

final _isoDateRe = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
final _dayMonthRe = RegExp(
  '$_lead(\\d{1,2})(?:st|nd|rd|th)?\\s+$_month(?:\\s+(\\d{4}))?\\b',
  caseSensitive: false,
);
final _monthDayRe = RegExp(
  '$_lead$_month\\s+(\\d{1,2})(?:st|nd|rd|th)?\\b(?:,?\\s+(\\d{4}))?',
  caseSensitive: false,
);
final _numericDateRe = RegExp(
  '$_lead(\\d{1,2})[/-](\\d{1,2})(?:[/-](\\d{2,4}))?\\b',
  caseSensitive: false,
);
final _relativeRe = RegExp(
  r'\b(?:by\s+|on\s+|due\s+|before\s+|next\s+|this\s+)?(today|tonight|tomorrow|tmrw|(mon|tue|wed|thu|fri|sat|sun)(?:day|s|sday|nesday|rsday|urday)?)\b',
  caseSensitive: false,
);

final _iOweRe = RegExp(
  r"(\bi owe\b|^owe\b|\bi have to (?:give|return|pay back)\b|\bowe to\b|\bborrowed from\b|\btook (?:a )?loan from\b|\bdibo\b|\bdebt to\b)",
  caseSensitive: false,
);
final _theyOweRe = RegExp(
  r"\b(owes? me|owes|will (?:give|return|pay) me|lent(?: to)?|gave (?:a )?loan to|pabo|paona|to receive from|receivable from)\b",
  caseSensitive: false,
);
const _personFiller = {
  'me', 'i', 'to', 'from', 'the', 'a', 'an', 'my', 'will', 'give', 'return', //
  'pay', 'back', 'have', 'loan', 'took', 'for', 'of', 'and', 'by', 'on',
};

class _Line {
  _Line({
    required this.raw,
    required this.text,
    required this.bullet,
    required this.done,
    this.amount,
    this.date,
    this.owe,
    this.person,
  });

  final String raw;

  /// What is left once bullets, amounts and dates are read out of it.
  final String text;
  final bool bullet;
  final bool done;
  final double? amount;
  final DateTime? date;

  /// A [DealDirection] when the line is about who owes whom.
  final String? owe;
  final String? person;

  /// When the chat message holding this line was sent, if it came from one.
  DateTime? sentAt;

  bool get isSentence => RegExp(r'[.!?]$').hasMatch(raw) && raw.length > 30;

  static _Line parse(String rawLine, DateTime now) {
    var s = rawLine.trim();
    var bullet = false, done = false;
    final b = _bulletRe.firstMatch(s);
    if (b != null && b.end > 0) {
      bullet = true;
      final box = b.group(1), glyph = b.group(2);
      done =
          (box != null && box.trim().isNotEmpty) ||
          (glyph != null && glyph != '☐' && glyph != '❌');
      s = s.substring(b.end);
    }
    final strike = _strikeRe.firstMatch(s);
    if (strike != null) {
      done = true;
      s = strike.group(1)!;
    }

    final owe = _iOweRe.hasMatch(s)
        ? DealDirection.iOweThem
        : _theyOweRe.hasMatch(s)
        ? DealDirection.theyOweMe
        : null;

    double? amount;
    String rest = s;
    for (final re in [_moneyPrefix, _moneySuffix]) {
      final m = re.firstMatch(rest);
      if (m == null) continue;
      amount = _money(m.group(1)!, m.group(2));
      rest = rest.replaceRange(m.start, m.end, ' ');
      break;
    }

    DateTime? date;
    (date, rest) = _takeDate(rest, now);

    if (amount == null) {
      // "Eggs 120" prices the line; "Visit Japan 2027" does not. On a debt
      // line any number is the amount ("lent 2000 to Sabbir").
      final t =
          _moneyTrailing.firstMatch(rest) ??
          (owe != null ? _anyNumber.firstMatch(rest) : null);
      if (t != null) {
        final v = _money(t.group(1)!, null);
        final digits = t.group(1)!.replaceAll(RegExp(r'[^\d]'), '');
        final looksLikeYear =
            owe == null && digits.length == 4 && v >= 1900 && v <= 2100;
        if (digits.length >= 2 && !looksLikeYear) {
          amount = v;
          rest = rest.replaceRange(t.start, t.end, ' ');
        }
      }
    }

    final text = rest
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s:=\-–,]+|[\s:=\-–,]+$'), '')
        .trim();
    return _Line(
      raw: rawLine.trim(),
      text: text.isEmpty ? s.trim() : text,
      bullet: bullet,
      done: done,
      amount: amount,
      date: date,
      owe: owe,
      person: owe == null ? null : _person(text),
    );
  }
}

double _money(String digits, String? unit) {
  final v = double.tryParse(digits.replaceAll(',', '')) ?? 0;
  return switch (unit?.toLowerCase()) {
    'k' => v * 1000,
    'lakh' || 'lac' || 'lakhs' => v * 100000,
    _ => v,
  };
}

/// Reads one date phrase out of [s]. Day-first for numeric dates (as written
/// in Bangladesh).
(DateTime?, String) _takeDate(String s, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DateTime? at(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    return dt.month == m ? dt : null; // rejects 31 Feb
  }

  int year(String? y) {
    if (y == null) return now.year;
    final v = int.parse(y);
    return v < 100 ? 2000 + v : v;
  }

  int month(String name) =>
      _months.indexOf(name.toLowerCase().substring(0, 3)) + 1;

  for (final re in [
    _isoDateRe,
    _dayMonthRe,
    _monthDayRe,
    _numericDateRe,
    _relativeRe,
  ]) {
    final m = re.firstMatch(s);
    if (m == null) continue;
    DateTime? d;
    if (re == _isoDateRe) {
      d = at(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    } else if (re == _dayMonthRe) {
      d = at(year(m.group(3)), month(m.group(2)!), int.parse(m.group(1)!));
    } else if (re == _monthDayRe) {
      d = at(year(m.group(3)), month(m.group(1)!), int.parse(m.group(2)!));
    } else if (re == _numericDateRe) {
      d = at(year(m.group(3)), int.parse(m.group(2)!), int.parse(m.group(1)!));
    } else {
      final w = m.group(1)!.toLowerCase();
      if (w == 'today' || w == 'tonight') {
        d = today;
      } else if (w == 'tomorrow' || w == 'tmrw') {
        d = today.add(const Duration(days: 1));
      } else {
        final wd = _weekdays.indexOf(m.group(2)!.toLowerCase()) + 1;
        d = today.add(Duration(days: (wd - today.weekday) % 7));
      }
    }
    if (d != null) return (d, s.replaceRange(m.start, m.end, ' '));
  }
  return (null, s);
}

/// The name in "Rahim owes me", "lent Karim", "I owe Mitu": the words left
/// once the debt phrase and filler are gone. At most three words.
String? _person(String text) {
  final stripped = text
      .replaceAll(_iOweRe, ' ')
      .replaceAll(_theyOweRe, ' ')
      .replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), ' ');
  final words = stripped
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_personFiller.contains(w.toLowerCase()))
      .take(3)
      .toList();
  return words.isEmpty ? null : words.join(' ');
}

// ── Blocks ──────────────────────────────────────────────────────────────────

class _Block {
  _Block(this.title, {this.explicitTitle = true, this.table});
  String title;

  /// False when the title was made up (source name, first line).
  final bool explicitTitle;
  final List<String> lines = [];
  final List<DateTime?> sent = [];

  /// Set for CSV input: the parsed rows, header first.
  final List<List<String>>? table;
}

final _mdHeading = RegExp(r'^#{1,6}\s+(.+)$');
final _boldHeading = RegExp(r'^\*\*(.+?)\*\*:?$');
final _underline = RegExp(r'^(=+|-{3,})$');

String? _headingOf(String line) {
  final t = line.trim();
  if (t.isEmpty) return null;
  final md = _mdHeading.firstMatch(t);
  if (md != null) return md.group(1)!.trim();
  final bold = _boldHeading.firstMatch(t);
  if (bold != null) return bold.group(1)!.trim();
  if (_isBullet(t)) return null;
  if (t.endsWith(':') && t.length <= 48 && !t.contains(RegExp(r'\d{3,}'))) {
    return t.substring(0, t.length - 1).trim();
  }
  final letters = t.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.length >= 3 &&
      t.length <= 40 &&
      letters == letters.toUpperCase() &&
      !t.contains(RegExp(r'\d'))) {
    return t;
  }
  return null;
}

/// Splits plain text into titled blocks. Headings are markdown `#`, `**bold**`,
/// a short line ending in `:`, an ALL-CAPS line, a line over `===`/`---`, or
/// a short plain line that starts a paragraph of list lines.
List<_Block> _blocks(String text, String sourceName) {
  final lines = <String>[];
  // When each chat message was sent: an expense noted in a chat happened then.
  final sent = <DateTime?>[];
  for (final l in text.split('\n')) {
    if (_chatNoise.hasMatch(l)) continue;
    final chat = _chatPrefix.firstMatch(l);
    lines.add(chat == null ? l : l.substring(chat.end));
    sent.add(chat == null ? null : _chatDate(chat));
  }
  final blocks = <_Block>[];
  _Block? cur;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (_underline.hasMatch(line.trim())) continue;
    var heading = _headingOf(line);
    if (heading == null &&
        _underline.hasMatch(next) &&
        line.trim().isNotEmpty) {
      heading = line.trim();
    }
    if (heading == null && _startsParagraph(lines, i)) heading = line.trim();
    if (heading != null) {
      cur = _Block(heading);
      blocks.add(cur);
      continue;
    }
    if (line.trim().isEmpty) continue;
    if (cur == null) {
      cur = _Block(sourceName, explicitTitle: false);
      blocks.add(cur);
    }
    cur.lines.add(line);
    cur.sent.add(sent[i]);
  }
  return blocks;
}

/// Day-first, as WhatsApp writes dates in Bangladesh.
DateTime? _chatDate(RegExpMatch m) {
  final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
  var y = int.parse(m.group(3)!);
  if (y < 100) y += 2000;
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

/// "Bazaar\n- eggs\n- rice": a short, plain line right after a blank line
/// (or at the top) whose next line is a bullet or carries an amount.
bool _startsParagraph(List<String> lines, int i) {
  final t = lines[i].trim();
  if (t.isEmpty || t.length > 32 || i + 1 >= lines.length) return false;
  if (i > 0 && lines[i - 1].trim().isNotEmpty) return false;
  if (_isBullet(t) || RegExp(r'\d').hasMatch(t) || t.endsWith('.')) {
    return false;
  }
  final next = lines[i + 1].trim();
  if (next.isEmpty) return false;
  return _headingCat(t) != null ||
      _isBullet(next) ||
      _moneyPrefix.hasMatch(next) ||
      _moneySuffix.hasMatch(next) ||
      _moneyTrailing.hasMatch(next);
}

// ── CSV ─────────────────────────────────────────────────────────────────────

/// A delimited table (CSV / TSV / semicolons), or null for plain text.
List<_Block>? _looksLikeTable(String text, String name) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return null;
  final named = RegExp(r'\.(csv|tsv)$', caseSensitive: false).hasMatch(name);
  for (final d in const [',', '\t', ';']) {
    final rows = [for (final l in lines) _splitCsv(l, d)];
    final width = rows.first.length;
    if (width < 2) continue;
    final table = [
      for (final r in rows)
        if (r.length == width) r,
    ];
    if (table.length / rows.length < 0.8) continue;
    // "Rice, eggs, oil" pasted on a few lines is a list, not a table. Pasted
    // text counts as a table only with a column of numbers in it.
    final numeric = [
      for (var c = 0; c < width; c++)
        table.skip(1).where((r) => _plainNumber(r[c]) != null).length >=
            (table.length - 1) * 0.6,
    ].any((x) => x);
    if (!named && (table.length < 3 || !numeric)) continue;
    return [_Block('', table: table)];
  }
  return null;
}

double? _plainNumber(String c) =>
    double.tryParse(c.replaceAll(RegExp(r'[,\s৳$]'), ''));

List<String> _splitCsv(String line, String d) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cur.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == d && !quoted) {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(ch);
    }
  }
  out.add(cur.toString().trim());
  return out;
}

/// The first column whose header is one of [names], or (unless [exact])
/// contains one as a word ("Amount (৳)").
int? _column(List<String> header, List<String> names, {bool exact = false}) {
  for (var i = 0; i < header.length; i++) {
    final h = header[i].toLowerCase().trim();
    final words = h.split(RegExp(r'[\s_/()]+'));
    if (names.any((n) => h == n || (!exact && words.contains(n)))) {
      return i;
    }
  }
  return null;
}

// ── Compile ─────────────────────────────────────────────────────────────────

class _Ctx {
  _Ctx({
    required this.hash,
    required this.sourceName,
    required this.orderBase,
    required this.now,
  });
  final String hash;
  final String sourceName;
  final int orderBase;
  final DateTime now;
  final sections = <SectionSpec>[];
  final items = <Item>[];

  void emit(_Block b) {
    if (b.table != null) return _emitTable(b.table!);
    if (b.lines.isEmpty) {
      // A heading with nothing under it still says where things will go.
      final cat = _headingCat(b.title);
      if (cat == null) return;
      _section(b.title, _shapeFor(cat), const []);
      return;
    }
    final parsed = [
      for (var i = 0; i < b.lines.length; i++)
        _Line.parse(b.lines[i], now)..sentAt = b.sent[i],
    ];
    final cat = _classify(b, parsed);
    if (cat != null) {
      _section(b.title, _shapeFor(cat), parsed);
      return;
    }
    // No heading and mixed content (a chat with yourself): sort line by line.
    final buckets = <_Cat, List<_Line>>{};
    for (final l in parsed) {
      final c = l.owe != null
          ? _Cat.people
          : l.amount != null
          ? (_hasKeyword(l.text, _Cat.shopping) ? _Cat.shopping : _Cat.spend)
          : _hasKeyword(l.text, _Cat.shopping)
          ? _Cat.shopping
          : _hasKeyword(l.text, _Cat.goals)
          ? _Cat.goals
          : l.isSentence
          ? _Cat.notes
          : _Cat.todo;
      buckets.putIfAbsent(c, () => []).add(l);
    }
    for (final e in buckets.entries) {
      final shape = _shapeFor(e.key);
      final title = '${kDomainTitles[_domainOf(shape)]} · ${b.title}';
      _section(title, shape, e.value);
    }
  }

  /// The category of a block: its heading's keywords, unless the content
  /// clearly disagrees, else what most of its lines look like. Null means
  /// "mixed, no heading": sort it line by line.
  _Cat? _classify(_Block b, List<_Line> lines) {
    final n = lines.length;
    double frac(bool Function(_Line) f) => lines.where(f).length / n;
    final owe = frac((l) => l.owe != null);
    final money = frac((l) => l.amount != null);
    final dated = frac((l) => l.date != null);
    final prose = frac((l) => l.isSentence);
    final avgLen = lines.fold<int>(0, (a, l) => a + l.raw.length) / n;

    final _Cat byContent;
    if (owe >= 0.5) {
      byContent = _Cat.people;
    } else if (money >= 0.6) {
      byContent = dated >= 0.5 ? _Cat.spend : _Cat.budget;
    } else if (avgLen > 70 || prose >= 0.5 || (n == 1 && avgLen > 40)) {
      byContent = _Cat.notes;
    } else {
      byContent = _Cat.todo;
    }

    final h = b.explicitTitle ? _headingCat(b.title) : null;
    if (h == null) {
      if (b.explicitTitle || n < 3) return byContent;
      // No heading: one kind of line (all debts, all prices, all plain) is a
      // list; a mix is a dump to sort line by line.
      final debts = frac((l) => l.owe != null);
      final priced = frac((l) => l.owe == null && l.amount != null);
      final plain = 1 - debts - priced;
      final dominant = [debts, priced, plain].reduce((a, b) => a > b ? a : b);
      return dominant >= 0.8 ? byContent : null;
    }
    // A money heading over lines without money is a plan in words: notes.
    if ((h == _Cat.budget || h == _Cat.spend) && money < 0.3) {
      return byContent == _Cat.todo && prose < 0.5 ? _Cat.todo : _Cat.notes;
    }
    if (h == _Cat.people && owe == 0 && money < 0.3) return byContent;
    if (h == _Cat.budget && dated >= 0.5) return _Cat.spend;
    return h;
  }

  void _section(String title, _Shape shape, List<_Line> lines) {
    final index = sections.length;
    final id = 'cv-${hash.substring(0, 8)}-$index';
    final spec = SectionSpec(
      id: id,
      title: title,
      type: shape.type,
      kind: shape.kind,
      domain: _domainOf(shape),
      order: orderBase + index,
    );
    sections.add(spec);
    if (shape.type == SectionType.notes) {
      if (lines.isEmpty) return;
      _add(
        spec,
        0,
        Item()
          ..kind = ItemKind.note
          ..title = title
          ..note = lines.map((l) => l.raw).join('\n'),
      );
      return;
    }
    for (var i = 0; i < lines.length; i++) {
      _add(spec, i, _itemFor(shape.kind, lines[i], title, now));
    }
  }

  void _add(SectionSpec spec, int i, Item item) {
    if (items.length >= _maxItemsPerSource) return;
    items.add(
      item
        // Same source, same place → same uuid, so a re-import never doubles.
        ..uuid = const Uuid().v5(Namespace.url.value, 'lm-canvas/${spec.id}/$i')
        ..section = spec.id
        ..sortOrder = i,
    );
  }

  void _emitTable(List<List<String>> rows) {
    final first = rows.first;
    final hasHeader = first.every(
      (c) => c.isEmpty || double.tryParse(c.replaceAll(',', '')) == null,
    );
    final header = hasHeader
        ? first
        : [for (var i = 0; i < first.length; i++) 'Column ${i + 1}'];
    final data = hasHeader ? rows.skip(1).toList() : rows;
    if (data.isEmpty) return;

    // Sign kept: a bank export marks money out as negative.
    double? num(String c) => _plainNumber(c) ?? _Line.parse(c, now).amount;

    bool mostly(int col, bool Function(String) f) =>
        data.where((r) => r[col].isNotEmpty && f(r[col])).length /
            data.length >=
        0.6;

    var amountCol = _column(header, const [
      'amount', 'cost', 'price', 'tk', 'taka', 'bdt', 'total', 'value', //
      'spent', 'debit', 'expense', 'income', 'credit',
    ]);
    if (amountCol != null && !mostly(amountCol, (c) => num(c) != null)) {
      amountCol = null;
    }
    final dateCol = [
      for (var i = 0; i < header.length; i++)
        if (i != amountCol && mostly(i, (c) => _takeDate(c, now).$1 != null)) i,
    ].firstOrNull;
    amountCol ??= [
      for (var i = 0; i < header.length; i++)
        if (i != dateCol && mostly(i, (c) => num(c) != null)) i,
    ].firstOrNull;
    final categoryCol = _column(header, const [
      'category',
      'type',
      'head',
      'bucket',
      'group',
      'tag',
      'kind',
    ]);
    final statusCol = _column(header, const [
      'done',
      'status',
      'paid',
      'bought',
      'complete',
      'completed',
    ], exact: true);
    final titleCol =
        _column(header, const [
          'item', 'description', 'name', 'title', 'details', 'particulars', //
          'purpose', 'note', 'task', 'what',
        ]) ??
        [
          for (var i = 0; i < header.length; i++)
            if (i != amountCol && i != dateCol && i != categoryCol) i,
        ].firstOrNull ??
        0;

    final isMoney = amountCol != null;
    final kind = !isMoney
        ? ItemKind.task
        : dateCol != null
        ? ItemKind.txn
        : ItemKind.budget;
    final shape = _Shape(
      isMoney ? SectionType.ledger : SectionType.checklist,
      kind,
    );
    final index = sections.length;
    final spec = SectionSpec(
      id: 'cv-${hash.substring(0, 8)}-$index',
      title: sourceName,
      type: shape.type,
      kind: kind,
      domain: _domainOf(shape),
      order: orderBase + index,
    );
    sections.add(spec);
    final incomeHeader =
        amountCol != null &&
        RegExp(
          r'income|credit|earn',
          caseSensitive: false,
        ).hasMatch(header[amountCol]);
    final signed =
        amountCol != null && data.any((r) => (num(r[amountCol!]) ?? 0) < 0);

    for (var r = 0; r < data.length; r++) {
      final row = data[r];
      final title = row[titleCol].trim();
      if (title.isEmpty && (amountCol == null || row[amountCol].isEmpty)) {
        continue;
      }
      final cat = categoryCol == null ? null : row[categoryCol];
      final rawAmount = amountCol == null ? null : num(row[amountCol]);
      final status = statusCol == null ? '' : row[statusCol].toLowerCase();
      final extras = [
        for (var i = 0; i < header.length; i++)
          if (i != titleCol &&
              i != amountCol &&
              i != dateCol &&
              i != categoryCol &&
              i != statusCol &&
              row[i].isNotEmpty)
            '${header[i]}: ${row[i]}',
      ];
      final item = Item()
        ..kind = kind
        ..title = title.isEmpty ? (cat ?? 'Row ${r + 1}') : title
        ..note = extras.join(' · ')
        ..amount = rawAmount?.abs()
        ..done = const {
          'yes',
          'y',
          'done',
          'paid',
          'true',
          '✓',
          'x',
          '1',
        }.contains(status.trim());
      if (kind == ItemKind.txn) {
        final earn =
            incomeHeader ||
            RegExp(
              r'income|earn|salary|credit|received',
              caseSensitive: false,
            ).hasMatch(cat ?? '') ||
            (rawAmount != null &&
                rawAmount > 0 &&
                (signed || row[amountCol!].trim().startsWith('+')));
        item
          ..direction = earn ? TxnDirection.earn : TxnDirection.spend
          ..category = (cat?.isEmpty ?? true) ? null : cat
          ..dueDate = _takeDate(row[dateCol!], now).$1 ?? now;
      } else if (kind == ItemKind.budget) {
        item.category = _budgetBucket('${cat ?? ''} $title');
      }
      _add(spec, r, item);
    }
  }
}

class _Shape {
  const _Shape(this.type, this.kind);
  final SectionType type;
  final String kind;
}

_Shape _shapeFor(_Cat c) => switch (c) {
  _Cat.people => const _Shape(SectionType.people, ItemKind.deal),
  _Cat.spend => const _Shape(SectionType.ledger, ItemKind.txn),
  _Cat.budget => const _Shape(SectionType.ledger, ItemKind.budget),
  _Cat.shopping => const _Shape(SectionType.checklist, ItemKind.buy),
  _Cat.goals => const _Shape(SectionType.goals, ItemKind.dream),
  _Cat.todo => const _Shape(SectionType.checklist, ItemKind.task),
  _Cat.notes => const _Shape(SectionType.notes, ItemKind.note),
};

Domain _domainOf(_Shape s) => switch (s.type) {
  SectionType.ledger => Domain.money,
  SectionType.people => Domain.people,
  SectionType.notes => Domain.notes,
  SectionType.goals => Domain.goals,
  SectionType.checklist =>
    s.kind == ItemKind.buy ? Domain.shopping : Domain.todo,
};

final _savingsRe = RegExp(
  r'\b(sav(e|ing|ings)|dps|fdr|invest\w*|sip|emergency|fund|debt|loan|emi)\b',
  caseSensitive: false,
);
final _needsRe = RegExp(
  r'\b(needs?|rent|bills?|electric\w*|gas|water|internet|wifi|food|grocer\w*|bazaa?r|transport|bus|fuel|school|tuition|fees?|medicine|doctor|utilit\w*|phone|mobile|maid|insurance|house)\b',
  caseSensitive: false,
);

String _budgetBucket(String text) {
  final t = text.toLowerCase();
  if (t.contains('want')) return BudgetCategory.wants;
  if (_savingsRe.hasMatch(t)) return BudgetCategory.savings;
  if (_needsRe.hasMatch(t)) return BudgetCategory.needs;
  return BudgetCategory.wants;
}

/// One parsed line as a row of [kind]. The original line is kept in the note
/// whenever the title lost something, so nothing the user wrote is dropped.
Item _itemFor(String kind, _Line l, String sectionTitle, DateTime now) {
  final item = Item()
    ..kind = kind
    ..title = l.text
    ..amount = l.amount
    ..done = l.done
    ..note = '';
  switch (kind) {
    case ItemKind.deal:
      item
        ..title = l.person ?? l.text
        ..direction = l.owe ?? DealDirection.iOweThem
        ..note = l.raw;
    case ItemKind.txn:
      final earn = RegExp(
        r'\b(salary|income|received|got|earned|bonus|refund)\b|^\+',
        caseSensitive: false,
      ).hasMatch(l.raw);
      item
        ..direction = earn ? TxnDirection.earn : TxnDirection.spend
        ..category = sectionTitle
        ..dueDate = l.date ?? l.sentAt ?? now;
    case ItemKind.budget:
      item.category = _budgetBucket('$sectionTitle ${l.text}');
    case ItemKind.note:
      item
        ..title = l.raw.length > 40 ? '${l.raw.substring(0, 40)}…' : l.raw
        ..note = l.raw;
    default:
      item.dueDate = l.date;
  }
  if (item.note.isEmpty && l.date != null && kind != ItemKind.task) {
    item.note = l.raw;
  }
  return item;
}
