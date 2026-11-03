import 'index_models.dart';

class IndexReferenceRange {
  const IndexReferenceRange(this.first, this.last);
  final IndexOccurrence first;
  final IndexOccurrence last;
  String get label => first.cue.id == last.cue.id
      ? 'Passage ${first.cue.id}'
      : 'Passages ${first.cue.id}–${last.cue.id}';
}

/// Presentation grouping only: retain all original extraction evidence.
/// Successive hits fewer than 30 passage numbers apart share a range.
/// Passage numbers are local to an episode's transcript/audio edition.
List<IndexReferenceRange> groupIndexReferences(
  Iterable<IndexOccurrence> occurrences,
) {
  final editions = <(String, String, String?), Map<int, IndexOccurrence>>{};
  for (final occurrence in occurrences) {
    final document = occurrence.document;
    final key = (
      document.episode.guid,
      document.edition,
      document.transcript.audioIdentity,
    );
    editions
        .putIfAbsent(key, () => {})
        .putIfAbsent(occurrence.cue.id, () => occurrence);
  }
  final result = <IndexReferenceRange>[];
  for (final passages in editions.values) {
    final ids = passages.keys.toList()..sort();
    IndexOccurrence? first;
    IndexOccurrence? last;
    for (final id in ids) {
      final occurrence = passages[id]!;
      if (last != null && id - last.cue.id >= 30) {
        result.add(IndexReferenceRange(first!, last));
        first = null;
      }
      first ??= occurrence;
      last = occurrence;
    }
    if (first != null && last != null) {
      result.add(IndexReferenceRange(first, last));
    }
  }
  return result;
}
