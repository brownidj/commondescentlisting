import 'package:flutter/material.dart';

import '../../models/catalogue.dart';

String displayTime(Duration time) {
  final hours = time.inHours.toString().padLeft(2, '0');
  final minutes = (time.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (time.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

class SegmentCard extends StatelessWidget {
  const SegmentCard({required this.segment, super.key});
  final Segment segment;

  @override
  Widget build(BuildContext context) {
    final title = segment.title?.trim();
    final label = segment.label?.trim();
    return Card(
      key: ValueKey('segment-${segment.sessionId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(segment.type, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              title == null || title.isEmpty
                  ? (segment.isNews ? 'News section' : 'Untitled segment')
                  : title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (label != null && label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(label),
            ],
            const SizedBox(height: 8),
            Text(
              segment.startTime == null
                  ? (segment.isNews
                        ? 'Item time unavailable'
                        : 'Time unavailable')
                  : 'Starts at ${displayTime(segment.startTime!)}',
            ),
            if (segment.newsStartTime != null) ...[
              const SizedBox(height: 4),
              Text(
                'News section starts at ${displayTime(segment.newsStartTime!)}',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
