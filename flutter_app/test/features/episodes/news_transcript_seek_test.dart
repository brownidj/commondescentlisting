import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/features/episodes/segment_card.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/current_transcript.dart';
import 'package:common_descent_listing/services/news_transcript_seek.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;

Episode newsEpisode({bool duplicate = false}) {
  final segments = <Segment>[
    for (final row in [
      (0, 'Arctic hyenas'),
      (1, 'dinosaur bone bacteria'),
      (2, 'a big trilobite'),
      if (duplicate) (3, 'more trilobites'),
    ])
      Segment(
        sourceIndex: row.$1,
        guid: 'episode',
        episodeTitle: 'Paleoart',
        episodeNumber: '64',
        type: 'News',
        title: row.$2,
        newsStartTime: const Duration(seconds: 10),
        audioUrl: 'https://example.com/audio.mp3',
      ),
    const Segment(
      sourceIndex: 4,
      guid: 'episode',
      episodeTitle: 'Paleoart',
      type: 'Main Discussion',
      startTime: Duration(seconds: 600),
    ),
  ];
  return Episode(
    guid: 'episode',
    title: 'Paleoart',
    number: '64',
    segments: segments,
  );
}

CurrentTranscript newsDocument(
  Episode episode, {
  bool competing = false,
  Duration offset = Duration.zero,
}) {
  final rows = [
    (15, 'Arctic hyenas, dinosaur bone bacteria, and a big trilobite.'),
    (30, 'Arctic hyenas were found.'),
    (180, 'My news is about a big trilobite.'),
    (190, 'This trilobite was enormous.'),
    if (competing) (450, 'Another trilobite was discovered.'),
    (650, 'A trilobite in the main discussion.'),
  ];
  return CurrentTranscript(
    episode: episode,
    edition: 'fixed',
    syncOffset: offset,
    transcript: EpisodeTranscript(
      episodeGuid: episode.guid,
      label: 'Test',
      note: '',
      audioIdentity: 'sha256:fixed',
      cues: [
        for (var i = 0; i < rows.length; i++)
          TranscriptCue(
            id: i + 1,
            start: Duration(seconds: rows[i].$1),
            end: Duration(seconds: rows[i].$1 + 5),
            text: rows[i].$2,
            originalText: rows[i].$2,
            reviewNotes: const [],
          ),
      ],
    ),
  );
}

void main() {
  test('last news matches its passage, skips preview/main discussion and applies offset', () {
    final e = newsEpisode();
    final d = newsDocument(e, offset: const Duration(seconds: 2));
    final result = matchNewsPassage(e, e.segments[2], d);
    expect(result.cue?.id, 3);
    expect(result.time, const Duration(seconds: 178));
    expect(result.message, contains('not a verified story boundary'));
  });
  test(
    'competing and duplicate topic matches fall back honestly to section time',
    () {
      final e = newsEpisode();
      final d = newsDocument(e, competing: true);
      final ambiguous = matchNewsPassage(e, e.segments[2], d);
      expect(ambiguous.cue, isNull);
      expect(ambiguous.time, const Duration(seconds: 10));
      expect(ambiguous.message, contains('whole news section'));
      final duplicate = newsEpisode(duplicate: true);
      expect(
        matchNewsPassage(
          duplicate,
          duplicate.segments[2],
          newsDocument(duplicate),
        ).cue,
        isNull,
      );
    },
  );
  testWidgets(
    'selected-item Play seeks to matched passage without selection-as-playback styling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final e = newsEpisode();
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            home: Scaffold(
              body: EpisodeDetail(
                episode: e,
                selectedSegmentId: e.segments[2].sessionId,
                newsTranscriptAvailable: (_) => true,
                newsAudioMatches: (_) => true,
                loadNewsTranscript: (_) async =>
                    newsDocument(e, offset: const Duration(seconds: 2)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('episode-play')));
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(seconds: 178));
      expect(
        find.textContaining('Transcript match: passage 3'),
        findsOneWidget,
      );
      expect(find.text('Selected news item'), findsNothing);
      expect(
        tester
            .widgetList<SegmentCard>(find.byType(SegmentCard))
            .every((c) => !c.selected),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing or mismatched transcript uses explicit section fallback',
    (tester) async {
      final e = newsEpisode();
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      for (final available in [false, true]) {
        await tester.pumpWidget(
          PlaybackScope(
            controller: player,
            child: MaterialApp(
              home: Scaffold(
                body: EpisodeDetail(
                  key: ValueKey(available),
                  episode: e,
                  selectedSegmentId: e.segments[2].sessionId,
                  newsTranscriptAvailable: (_) => available,
                  newsAudioMatches: (_) => false,
                  loadNewsTranscript: (_) async => newsDocument(e),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('episode-play')));
        await tester.pumpAndSettle();
        expect(audio.position, const Duration(seconds: 10));
        expect(find.text('Selected news item'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
