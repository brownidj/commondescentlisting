import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_reference_ranges.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  test(
    'sorts passage IDs, keeps first duplicate and collapses nearby hits',
    () {
      final document = indexDocument(List.generate(7, (i) => 'Text $i'));
      IndexOccurrence at(int i) =>
          (document: document, cue: document.transcript.cues[i]);
      final original = at(1);
      final ranges = groupIndexReferences([
        at(3),
        at(0),
        original,
        at(1),
        at(2),
        at(5),
        at(6),
      ]);
      expect(ranges.map((r) => r.label), ['Passages 1–7']);
      expect(ranges.first.first.cue, document.transcript.cues.first);
      final duplicates = groupIndexReferences([original, at(1)]);
      expect(duplicates.single.label, 'Passage 2');
      expect(duplicates.single.first, original);
      expect(groupIndexReferences([]), isEmpty);
    },
  );

  test('chains gaps below 30 but keeps gaps of exactly 30 separate', () {
    final document = indexDocument(List.generate(100, (i) => 'Text $i'));
    IndexOccurrence at(int id) =>
        (document: document, cue: document.transcript.cues[id - 1]);
    final ranges = groupIndexReferences([
      at(89),
      at(30),
      at(1),
      at(59),
      at(30),
      at(90),
    ]);
    expect(ranges.map((r) => r.label), ['Passages 1–59', 'Passages 89–90']);
    expect(ranges.first.first.cue.id, 1);
    expect(ranges.first.last.cue.id, 59);
    expect(groupIndexReferences([at(1), at(31)]).map((r) => r.label), [
      'Passage 1',
      'Passage 31',
    ]);
  });

  test('never merges passages across different episodes or editions', () {
    final first = indexDocument(['First', 'Second']);
    final otherEdition = indexDocument(['First', 'Second'], edition: 'two');
    final otherEpisode = CurrentTranscript(
      episode: Episode(
        guid: 'other',
        title: 'Other',
        number: null,
        segments: const [],
      ),
      edition: first.edition,
      syncOffset: Duration.zero,
      transcript: EpisodeTranscript(
        episodeGuid: 'other',
        label: 'Fixture',
        note: '',
        cues: first.transcript.cues,
        audioIdentity: first.transcript.audioIdentity,
      ),
    );
    final ranges = groupIndexReferences([
      (document: first, cue: first.transcript.cues.first),
      (document: otherEpisode, cue: otherEpisode.transcript.cues.last),
      (document: otherEdition, cue: otherEdition.transcript.cues.last),
    ]);
    expect(ranges.map((r) => r.label), ['Passage 1', 'Passage 2', 'Passage 2']);
    expect(ranges, hasLength(3));
  });
}
