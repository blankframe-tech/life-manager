import 'package:flutter/material.dart';

/// Asks for a transaction category name. Resolves to the raw text (untrimmed)
/// or null if dismissed.
Future<String?> promptForCategory(BuildContext context) => showDialog<String>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );

/// A [StatefulWidget] purely so the dialog owns its own controller.
///
/// The obvious alternative — create a controller next to the `showDialog`
/// call and dispose it once that future completes — throws "A
/// TextEditingController was used after being disposed": the future resolves
/// when the route is popped, while the dialog is still animating out and its
/// [TextField] is still building against the controller.
class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'e.g. Rent'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
