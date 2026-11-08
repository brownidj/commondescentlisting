import 'package:flutter/material.dart';

import '../indexes/index_controller.dart';
import '../indexes/index_details.dart';
import '../indexes/index_engine.dart';
import '../indexes/index_entity_dialog.dart';
import '../indexes/index_models.dart';

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    ) ??
    false;

/// Explicit, local-only fallback; never silently scans or creates an entry.
Future<void> offerEpisodeTranscriptSearch({
  required BuildContext context,
  required String query,
  required KnowledgeIndexController knowledge,
  required Set<String> episodeGuids,
  required bool Function() isCurrent,
  required void Function(Iterable<String>) onResults,
}) async {
  if (!await _confirm(
    context,
    'Search transcript text?',
    'No index matches were found for “$query” with the current episode filters. '
        'Would you like to search the available transcript text directly?',
  )) {
    return;
  }
  if (!context.mounted || !isCurrent()) {
    return;
  }
  final probe = IndexEntity(id: 'search', kind: IndexKind.fossil, name: query);
  final hits = indexOccurrences(
    probe,
    knowledge.documents,
  ).where((hit) => episodeGuids.contains(hit.document.episode.guid)).toList();
  onResults(hits.map((hit) => hit.document.episode.guid));
  if (hits.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No transcript matches'),
        content: Text(
          '“$query” was not found in the available transcript text '
          'with the current episode filters.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }
  final entry = IndexEntity(
    id: 'manual:${DateTime.now().microsecondsSinceEpoch}',
    kind: IndexKind.fossil,
    name: query,
    anchors: [
      for (final hit in hits)
        IndexAnchor(
          guid: hit.document.episode.guid,
          quote: hit.cue.text,
          passageId: hit.cue.id,
          edition: hit.document.edition,
          passageText: hit.cue.text,
        ),
    ],
    details: IndexDetails(
      spoken: [query],
      confidence: 'unreviewed',
      description:
          'Literal transcript search results; category requires review.',
    ),
  );
  final problem = knowledge.additionProblem(entry);
  if (!await _confirm(
    context,
    'Add results to the index?',
    'Found ${hits.length} matching passages in '
        '${hits.map((hit) => hit.document.episode.guid).toSet().length} episodes. '
        'Would you like to add these results to the index?',
  )) {
    return;
  }
  if (!context.mounted || !isCurrent()) {
    return;
  }
  if (problem != null) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Entry cannot be added'),
        content: Text(problem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }
  final revision = knowledge.registryRevision;
  final edited = await showDialog<IndexEntity>(
    context: context,
    builder: (_) => IndexEntityDialog(
      kind: entry.kind,
      entities: knowledge.entities,
      entity: entry,
      validateEntry: knowledge.additionProblem,
    ),
  );
  if (edited == null || !context.mounted || !isCurrent()) {
    return;
  }
  try {
    // Reload exact editions/corrections before adopting the saved evidence.
    await knowledge.refresh();
    if (!context.mounted || !isCurrent()) {
      return;
    }
    if (knowledge.error != null) {
      throw StateError(knowledge.error!);
    }
    if (knowledge.registryRevision != revision) {
      throw StateError(
        'The index changed during review. Search again before adding.',
      );
    }
    for (final anchor in edited.anchors) {
      final document = knowledge.documents
          .where(
            (d) => d.episode.guid == anchor.guid && d.edition == anchor.edition,
          )
          .firstOrNull;
      if (document == null ||
          !document.transcript.cues.any(
            (cue) =>
                cue.id == anchor.passageId && cue.text == anchor.passageText,
          )) {
        throw StateError(
          'The transcript changed during review. Search again before adding.',
        );
      }
    }
    await knowledge.saveEntity(edited, expectedRevision: revision);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Index entry saved.')));
    }
  } catch (error) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Entry was not added'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}
