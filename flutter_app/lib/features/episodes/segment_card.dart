import 'package:flutter/material.dart';

import '../../models/catalogue.dart';

String displayTime(Duration time) {
  final hours = time.inHours.toString().padLeft(2, '0');
  final minutes = (time.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

class SegmentCard extends StatelessWidget {
  const SegmentCard({
    required this.segment,
    this.selected = false,
    this.onOpenTime,
    super.key,
  });
  final Segment segment;
  final bool selected;
  final ValueChanged<Duration>? onOpenTime;

  Widget _timestamp(String text, Duration time) {
    final open = onOpenTime;
    if (open == null) return Text(text);
    return Tooltip(
      message: 'Play here from ${displayTime(time)}',
      child: TextButton.icon(
        onPressed: () => open(time),
        icon: const Icon(Icons.play_arrow),
        label: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = segment.title?.trim();
    final label = segment.label?.trim();
    final isDiscussion = segment.type == 'Main Discussion';
    final displayTitle = title == null || title.isEmpty
        ? (segment.isNews ? 'News section' : 'Untitled segment')
        : title;
    final discussionPart = isDiscussion
        ? label
              ?.replaceFirst(
                RegExp(r'^main discussion\s*[,\-:]?\s*', caseSensitive: false),
                '',
              )
              .trim()
        : null;
    return Card(
      key: ValueKey('segment-${segment.sessionId}'),
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selected) const Text('Selected news item'),
            if (!segment.isNews && !isDiscussion) ...[
              Text(segment.type, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
            ],
            Text(
              discussionPart != null && discussionPart.isNotEmpty
                  ? '$displayTitle - $discussionPart'
                  : displayTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!isDiscussion && label != null && label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(label),
            ],
            if (segment.startTime != null || !segment.isNews) ...[
              const SizedBox(height: 8),
              if (segment.startTime == null)
                const Text('Time unavailable')
              else
                _timestamp(
                  'Starts at ${displayTime(segment.startTime!)}',
                  segment.startTime!,
                ),
            ],
            if (segment.newsStartTime != null) ...[
              const SizedBox(height: 4),
              _timestamp(
                'News section starts at ${displayTime(segment.newsStartTime!)}',
                segment.newsStartTime!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
