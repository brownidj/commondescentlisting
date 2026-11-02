import 'package:common_descent_listing/features/episodes/transcript_search.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cues = [
    TranscriptCue(
      id: 1,
      start: Duration.zero,
      end: Duration(seconds: 10),
      text: 'Karoo and KAROO (fossils).',
      originalText: 'Karu and KARU (fossils).',
      reviewNotes: ['Review a different word: Jurassic.'],
    ),
    TranscriptCue(
      id: 2,
      start: Duration(seconds: 10),
      end: Duration(seconds: 20),
      text: 'Some more fossils.',
      originalText: 'Some more fossils.',
      reviewNotes: [],
    ),
  ];

  test('case-insensitive trimmed query preserves passage order and ranges', () {
    final search = TranscriptSearch('  kArOo  ');
    expect(search.filter(cues, original: false).map((c) => c.id), [1]);
    expect(search.matches(cues.first.text).map((m) => m.group(0)), [
      'Karoo',
      'KAROO',
    ]);
    expect(TranscriptSearch('fossils').filter(cues, original: false), cues);
    expect(TranscriptSearch('  ').filter(cues, original: false), cues);
  });

  test('literal punctuation, current text mode and no matches', () {
    expect(TranscriptSearch('(fossils).').filter(cues, original: false), [
      cues.first,
    ]);
    expect(TranscriptSearch('.*').filter(cues, original: false), isEmpty);
    expect(TranscriptSearch('Karoo').filter(cues, original: true), isEmpty);
    expect(TranscriptSearch('Karu').filter(cues, original: true), [cues.first]);
    expect(TranscriptSearch('Jurassic').filter(cues, original: false), isEmpty);
    expect(
      TranscriptSearch('not present').filter(cues, original: false),
      isEmpty,
    );
  });
}
