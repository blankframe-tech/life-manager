import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/item.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

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

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    _amount = TextEditingController(
        text: e?.amount == null ? '' : e!.amount!.toStringAsFixed(0));
    _direction = e?.direction ?? _defaultDirection();
    _category = e?.category ?? widget.initialCategory ?? _defaultCategory();
    _section = e?.section ?? widget.initialSection ?? _defaultSection();
    _dueDate = e?.dueDate;
  }

  String? _defaultDirection() =>
      widget.kind == ItemKind.deal ? DealDirection.iOweThem : null;
  String? _defaultCategory() =>
      widget.kind == ItemKind.budget ? BudgetCategory.needs : null;
  String? _defaultSection() {
    if (widget.kind == ItemKind.task) return 'admin';
    if (widget.kind == ItemKind.buy) return 'p0';
    return null;
  }

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
    final sync = ref.read(syncServiceProvider);
    final item = widget.existing ?? (Item()..uuid = const Uuid().v4());
    item.kind = widget.kind;
    item.title = title;
    item.note = _note.text.trim();
    item.amount = double.tryParse(_amount.text.trim());
    item.direction = widget.kind == ItemKind.deal ? _direction : null;
    item.category = widget.kind == ItemKind.budget ? _category : null;
    item.section =
        (widget.kind == ItemKind.task || widget.kind == ItemKind.buy)
            ? _section
            : null;
    item.dueDate = _dueDate;
    await sync.save(item);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final section = sectionFor(widget.kind);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: AppColors.hair,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Text(
                '${_isEdit ? 'Edit' : 'New'} ${section.label}',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              _field(_title, 'Title', autofocus: !_isEdit, maxLines: 2),
              const SizedBox(height: 10),
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
              if (widget.kind == ItemKind.task) ...[
                _segmented(
                  const {
                    'time': 'Time-sensitive',
                    'admin': 'Admin',
                    'declutter': 'Declutter',
                  },
                  _section,
                  (v) => setState(() => _section = v),
                ),
                const SizedBox(height: 10),
                _dueRow(),
                const SizedBox(height: 10),
              ],
              if (widget.kind == ItemKind.buy) ...[
                _segmented(
                  const {'p0': 'Priority 0', 'wishlist': 'Wishlist'},
                  _section,
                  (v) => setState(() => _section = v),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.kind == ItemKind.deal ||
                  widget.kind == ItemKind.budget ||
                  widget.kind == ItemKind.buy) ...[
                _field(_amount, 'Amount (৳, optional)',
                    keyboard: TextInputType.number),
                const SizedBox(height: 10),
              ],
              _field(_note, 'Notes (optional)', maxLines: 3),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: section.color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_isEdit ? 'Save changes' : 'Add',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint,
      {bool autofocus = false,
      int maxLines = 1,
      TextInputType? keyboard}) {
    return TextField(
      controller: c,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _segmented(
      Map<String, String> options, String? value, ValueChanged<String> onTap) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final selected = e.key == value;
        return GestureDetector(
          onTap: () => onTap(e.key),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: selected
                  ? sectionFor(widget.kind).color
                  : AppColors.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              e.value,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _dueRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _dueDate == null
                ? 'No due date'
                : 'Due ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
            style: const TextStyle(color: AppColors.inkSub, fontSize: 15),
          ),
        ),
        if (_dueDate != null)
          TextButton(
            onPressed: () => setState(() => _dueDate = null),
            child: const Text('Clear'),
          ),
        TextButton(
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _dueDate ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
            if (picked != null) setState(() => _dueDate = picked);
          },
          child: const Text('Pick date'),
        ),
      ],
    );
  }
}
