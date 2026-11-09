import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/item.dart';
import '../modules/module.dart';
import '../providers/providers.dart';
import '../services/txn_category_service.dart' show mergeUsedCategories;
import '../theme/app_theme.dart';
import 'new_category_dialog.dart';

final _dateLabel = DateFormat('EEE, d MMM yyyy');

/// Opens the add/edit sheet for a given [kind]. Pass [existing] to edit.
Future<void> showItemEditor(
  BuildContext context,
  WidgetRef ref,
  String kind, {
  Item? existing,
  String? initialCategory,
  String? initialSection,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ItemEditor(
      kind: kind,
      existing: existing,
      initialCategory: initialCategory,
      initialSection: initialSection,
    ),
  );
}

class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({
    required this.kind,
    this.existing,
    this.initialCategory,
    this.initialSection,
  });
  final String kind;
  final Item? existing;
  final String? initialCategory;
  final String? initialSection;

  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _amount;
  String? _direction;
  String? _category;
  String? _section;
  DateTime? _dueDate;

  /// Set when a transaction is saved without a usable amount — an entry in a
  /// spending log with no number in it is the one thing that can't be fixed
  /// later by reading the title.
  bool _amountMissing = false;

  bool get _isEdit => widget.existing != null;
  bool get _isTxn => widget.kind == ItemKind.txn;

  /// Field config for generic kinds (Tasks, Buy, Notes, custom categories),
  /// from the module that owns [ItemEditor.kind]. Null for a kind whose module
  /// has been removed from the config — the editor then shows title + notes.
  late final ItemSpec? _spec = ref.read(appConfigProvider).specFor(widget.kind);
  List<ListSection> get _sections => _spec?.sections ?? const [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _amount = TextEditingController(
      text: e?.amount == null ? '' : e!.amount!.toStringAsFixed(0),
    );
    _direction = e?.direction ?? _defaultDirection();
    _category = e?.category ?? widget.initialCategory ?? _defaultCategory();
    _section = e?.section ?? widget.initialSection ?? _defaultSection();
    // A transaction is nearly always logged the day it happened, so a new one
    // starts on today rather than making the user reach for the picker.
    _dueDate = e?.dueDate ?? (_isTxn ? DateTime.now() : null);
  }

  String? _defaultDirection() => switch (widget.kind) {
    ItemKind.deal => DealDirection.iOweThem,
    ItemKind.txn => TxnDirection.spend,
    _ => null,
  };

  String? _defaultCategory() {
    if (widget.kind == ItemKind.budget) return BudgetCategory.needs;
    if (_isTxn) {
      final categories = ref.read(txnCategoriesProvider);
      return categories.isEmpty ? null : categories.first;
    }
    return null;
  }

  String? _defaultSection() => _sections.isEmpty ? null : _sections.first.id;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final amount = double.tryParse(_amount.text.trim());
    if (_isTxn && (amount == null || amount <= 0)) {
      setState(() => _amountMissing = true);
      return;
    }
    HapticFeedback.lightImpact();
    final sync = ref.read(syncServiceProvider);
    final item = widget.existing ?? (Item()..uuid = const Uuid().v4());
    item.kind = widget.kind;
    item.title = title;
    item.note = _note.text.trim();
    item.amount = amount;
    item.direction = (widget.kind == ItemKind.deal || _isTxn)
        ? _direction
        : null;
    item.category = (widget.kind == ItemKind.budget || _isTxn)
        ? _category
        : null;
    item.section = _sections.isNotEmpty ? _section : null;
    item.dueDate = _dueDate;
    await sync.save(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final singular = _spec?.singular ?? 'Item';
    final customKind =
        _isTxn ||
        widget.kind == ItemKind.deal ||
        widget.kind == ItemKind.budget;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.hair,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Text(
                '${_isEdit ? 'Edit' : 'New'} $singular',
                style: context.text.headlineSmall,
              ),
              const SizedBox(height: 14),
              _field(_title, 'Title', autofocus: !_isEdit, maxLines: 2),
              const SizedBox(height: 10),
              if (_isTxn) ...[
                _segmented(
                  {TxnDirection.spend: 'Spent', TxnDirection.earn: 'Earned'},
                  _direction,
                  (v) => setState(() => _direction = v),
                ),
                const SizedBox(height: 12),
                _categoryPicker(),
                const SizedBox(height: 12),
                _field(
                  _amount,
                  'Amount (৳)',
                  keyboard: TextInputType.number,
                  onChanged: _amountMissing
                      ? (_) => setState(() => _amountMissing = false)
                      : null,
                ),
                if (_amountMissing)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      'Enter an amount above zero.',
                      style: TextStyle(color: c.negative, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                _dateRow(label: 'Date', clearable: false),
                const SizedBox(height: 10),
              ],
              if (widget.kind == ItemKind.deal) ...[
                _segmented(
                  {
                    DealDirection.iOweThem: 'I owe',
                    DealDirection.theyOweMe: 'They owe me',
                  },
                  _direction,
                  (v) => setState(() => _direction = v),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.kind == ItemKind.budget) ...[
                _segmented(
                  {
                    BudgetCategory.needs: 'Needs',
                    BudgetCategory.wants: 'Wants',
                    BudgetCategory.savings: 'Savings',
                  },
                  _category,
                  (v) => setState(() => _category = v),
                ),
                const SizedBox(height: 10),
              ],
              if (!customKind && _sections.isNotEmpty) ...[
                _segmented(
                  {for (final s in _sections) s.id: s.label},
                  _section,
                  (v) => setState(() => _section = v),
                ),
                const SizedBox(height: 10),
              ],
              if (!customKind && (_spec?.dueDate ?? false)) ...[
                _dateRow(label: 'Due'),
                const SizedBox(height: 10),
              ],
              if (widget.kind == ItemKind.deal ||
                  widget.kind == ItemKind.budget ||
                  (!customKind && (_spec?.amount ?? false))) ...[
                _field(
                  _amount,
                  'Amount (৳, optional)',
                  keyboard: TextInputType.number,
                ),
                const SizedBox(height: 10),
              ],
              _field(
                _note,
                _spec?.noteHint ?? 'Notes (optional)',
                maxLines: _spec?.noteLines ?? 3,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _save,
                child: Text(_isEdit ? 'Save changes' : 'Add $singular'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String hint, {
    bool autofocus = false,
    int maxLines = 1,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboard,
      onChanged: onChanged,
      style: context.text.bodyLarge,
      decoration: InputDecoration(hintText: hint),
    );
  }

  /// Native Cupertino segmented control — animated selection, correct
  /// accessibility semantics out of the box (replaces a hand-rolled Wrap of
  /// GestureDetectors that had no press feedback or a11y traits).
  Widget _segmented(
    Map<String, String> options,
    String? value,
    ValueChanged<String> onTap,
  ) {
    return CupertinoSlidingSegmentedControl<String>(
      groupValue: value,
      backgroundColor: context.colors.card,
      thumbColor: context.colors.primary,
      children: {
        for (final e in options.entries)
          e.key: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              e.value,
              style: TextStyle(
                color: e.key == value
                    ? context.colors.onPrimary
                    : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
      },
      onValueChanged: (v) {
        if (v != null) {
          HapticFeedback.selectionClick();
          onTap(v);
        }
      },
    );
  }

  /// Shared date row: the deadline on a task, the day the money moved on a
  /// transaction. Transactions pass [clearable] false — a logged transaction
  /// always happened on some day.
  Widget _dateRow({required String label, bool clearable = true}) {
    final date = _dueDate;
    return Row(
      children: [
        Expanded(
          child: Text(
            date == null
                ? 'No due date'
                : '$label · ${_dateLabel.format(date)}',
            style: TextStyle(color: context.colors.inkSub, fontSize: 15),
          ),
        ),
        if (clearable && date != null)
          TextButton(
            onPressed: () => setState(() => _dueDate = null),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: _pickDate,
          child: Text(date == null ? 'Pick date' : 'Change'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  /// Transaction categories as chips, plus a "New" chip that adds one without
  /// leaving the sheet — the moment you need a category is the moment you're
  /// logging something that doesn't fit the existing ones.
  Widget _categoryPicker() {
    final c = context.colors;
    // Includes whatever this row is already tagged with, even if that category
    // has since been removed (or came from another device — the list itself is
    // per-device), so opening an old transaction can't silently retag it.
    final options = mergeUsedCategories(ref.watch(txnCategoriesProvider), [
      _category,
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Category',
            style: TextStyle(
              color: c.inkSub,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in options)
              ChoiceChip(
                label: Text(name),
                selected: name == _category,
                showCheckmark: false,
                backgroundColor: c.card,
                selectedColor: context.colors.primary,
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: name == _category ? c.onPrimary : c.ink,
                ),
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  setState(() => _category = name);
                },
              ),
            ActionChip(
              avatar: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('New'),
              backgroundColor: c.card,
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
              onPressed: _promptNewCategory,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _promptNewCategory() async {
    final name = await promptForCategory(context);
    final clean = name?.trim() ?? '';
    if (clean.isEmpty || !mounted) return;
    final notifier = ref.read(txnCategoriesProvider.notifier);
    // `add` returns null for a duplicate; select the existing one rather than
    // doing nothing, since picking it is what the user meant either way.
    final added =
        notifier.add(clean) ??
        ref
            .read(txnCategoriesProvider)
            .firstWhere(
              (existing) => existing.toLowerCase() == clean.toLowerCase(),
              orElse: () => clean,
            );
    setState(() => _category = added);
  }
}
