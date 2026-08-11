import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Confirmation for "Delete all data".
///
/// Deliberately harder to dismiss than a normal dialog: the action clears the
/// cloud as well as this device, so it also takes the other device's copy, and
/// there is no undo. Requiring the word to be typed makes an accidental
/// double-tap impossible while still being one short step for someone who
/// means it.
class DeleteEverythingDialog extends StatefulWidget {
  const DeleteEverythingDialog({super.key, required this.cloud});

  /// Whether this build syncs — decides whether the cloud is mentioned at all.
  final bool cloud;

  @override
  State<DeleteEverythingDialog> createState() =>
      _DeleteEverythingDialogState();
}

class _DeleteEverythingDialogState extends State<DeleteEverythingDialog> {
  static const _phrase = 'DELETE';

  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _confirmed => _controller.text.trim().toUpperCase() == _phrase;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // The autofocused field raises the keyboard, which cuts the space the
      // dialog gets; without this the explanation and the field don't fit and
      // the content overflows off the bottom. Scrolling keeps every word
      // reachable instead of clipping the part that says it can't be undone.
      scrollable: true,
      title: const Text('Delete all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.cloud
                ? 'This erases every item and all activity history — on this '
                    'device and in the cloud, so it disappears from your other '
                    'devices too. Your settings are reset and you are signed '
                    'out.'
                : 'This erases every item and all activity history on this '
                    'device, and resets your settings.',
          ),
          const SizedBox(height: 12),
          const Text('It cannot be undone. Export your data first if you '
              'might want it back.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type $_phrase to confirm',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_confirmed) Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
