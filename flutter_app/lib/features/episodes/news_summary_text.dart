import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Avoids an EditableText/selection subtree inside animated expansion bodies.
/// Copy remains available without relying on selection-state reparenting.
class NewsSummaryText extends StatelessWidget {
  const NewsSummaryText({required this.text, super.key});
  final String text;

  Future<void> _copy(BuildContext context) async {
    var copied = false;
    try {
      await Clipboard.setData(ClipboardData(text: text));
      copied = true;
    } catch (_) {
      // Clipboard access may fail; preserve the readable summary.
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied
              ? 'Summary copied'
              : 'The summary could not be copied. Please try again.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy summary'),
          ),
        ],
      ),
    );
  }
}
