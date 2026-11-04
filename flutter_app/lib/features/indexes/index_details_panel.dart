import 'package:flutter/material.dart';

import '../../services/episode_link.dart';
import 'index_models.dart';

/// Compact entry provenance, accessible without repeating it in the result body.
String indexEntryTooltip(IndexEntity entity) {
  final details = entity.details;
  return [
    if (details == null && entity.note.isNotEmpty) entity.note,
    if (entity.externallyConfirmed)
      'Confirmed by external sources: ${entity.externalConfirmationSources.join(", ")}.',
    if (details != null) ...[
      if (details.spoken.isNotEmpty) 'Spoken: ${details.spoken.join("; ")}',
      'Model confidence: ${details.confidence.isEmpty ? "not recorded" : details.confidence} · '
          '${entity.review == IndexReview.suggested ? "Review required" : entity.review.name}',
      if (details.description.isNotEmpty) details.description,
      for (final reason in details.normalizations)
        'Proposed normalization: $reason',
      if (details.editorialNote.isNotEmpty) details.editorialNote,
      if (details.model.isNotEmpty) 'Extraction model: ${details.model}',
    ],
    ..._extractionSummary(entity),
    'Review status: ${entity.review.name}',
    if (entity.subtype.isNotEmpty) 'Classification: ${entity.subtype}',
  ].join('\n\n');
}

Iterable<String> _extractionSummary(IndexEntity entity) sync* {
  final groups = <String, List<double>>{};
  for (final anchor in entity.anchors) {
    for (final source in anchor.extraction) {
      final key =
          '${source.method} · ${source.label} · ${source.extractorVersion}';
      final scores = groups.putIfAbsent(key, () => []);
      if (source.score case final score?) {
        scores.add(score);
      }
    }
  }
  for (final group in groups.entries) {
    group.value.sort();
    final scores = group.value;
    final range = scores.isEmpty
        ? ''
        : scores.first == scores.last
        ? ' · model score ${scores.first.toStringAsFixed(3)}'
        : ' · model scores ${scores.first.toStringAsFixed(3)}–${scores.last.toStringAsFixed(3)}';
    yield 'Extraction evidence: ${group.key}$range (not human confirmation)';
  }
}

/// The offline trial's evidence-first presentation, rendered with native widgets.
class IndexDetailsPanel extends StatelessWidget {
  const IndexDetailsPanel({
    required this.entity,
    this.showReviewDetails = true,
    super.key,
  });
  final IndexEntity entity;
  final bool showReviewDetails;

  @override
  Widget build(BuildContext context) {
    final details = entity.details;
    if (details == null) {
      return showReviewDetails ? Text(entity.note) : const SizedBox.shrink();
    }
    // Internal text scroll offsets must never share an ExpansionTile's bool slot.
    Widget selectable(String text) =>
        PageStorage(bucket: PageStorageBucket(), child: SelectableText(text));
    Widget jsonBlock(String value) => Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: PageStorage(
        bucket: PageStorageBucket(),
        child: SelectableText(
          value,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showReviewDetails) ...[
          Text(
            '${entity.kind.label} / ${entity.subtype} · ${entity.review.name}',
          ),
          if (details.spoken.isNotEmpty)
            selectable('Spoken: ${details.spoken.join("; ")}'),
          Text(
            'Model confidence: ${details.confidence.isEmpty ? "not recorded" : details.confidence} · '
            '${entity.review == IndexReview.suggested ? "Review required" : entity.review.name}',
          ),
          if (details.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            selectable(details.description),
          ],
          for (final reason in details.normalizations)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: selectable('Proposed normalization: $reason'),
            ),
          if (details.editorialNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            selectable(details.editorialNote),
          ],
        ],
        if (details.bibliography.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Sourced bibliography — added during review',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          jsonBlock(details.bibliography),
        ],
        for (final source in details.sources)
          TextButton.icon(
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
            onPressed: () async {
              final opened = await openEpisodeLink(Uri.parse(source.url));
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Source could not be opened.')),
                );
              }
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text('Source: ${source.label}'),
          ),
        if (details.originalPublication.isNotEmpty)
          ExpansionTile(
            key: PageStorageKey('publication-fields-${entity.id}'),
            title: const Text(
              'Original model publication fields (transcript only)',
            ),
            children: [jsonBlock(details.originalPublication)],
          ),
        if (showReviewDetails && details.model.isNotEmpty)
          Text('Extraction model: ${details.model}'),
      ],
    );
  }
}
