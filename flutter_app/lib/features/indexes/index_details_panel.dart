import 'package:flutter/material.dart';

import '../../services/episode_link.dart';
import 'index_models.dart';

/// The offline trial's evidence-first presentation, rendered with native widgets.
class IndexDetailsPanel extends StatelessWidget {
  const IndexDetailsPanel({required this.entity, super.key});
  final IndexEntity entity;

  @override
  Widget build(BuildContext context) {
    final details = entity.details;
    if (details == null) {
      return Text(entity.note);
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
        if (details.model.isNotEmpty)
          Text('Extraction model: ${details.model}'),
      ],
    );
  }
}
