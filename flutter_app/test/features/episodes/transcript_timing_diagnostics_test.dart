import 'dart:convert';

import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/transcript_timing_diagnostics.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

void main() {
  final episode = Episode(
    guid: editableTranscript.episodeGuid,
    title: 'Timing test',
    number: '208',
    segments: [
      Segment(
        sourceIndex: 0,
        guid: editableTranscript.episodeGuid,
        episodeTitle: 'Timing test',
        type: 'Episode',
        audioUrl: 'https://example.com/audio.mp3',
      ),
    ],
  );

  test('report distinguishes raw error from calibrated residual', () {
    final measurements = TranscriptTimingDiagnostics(episode.guid);
    final sample = TranscriptTimingSample(
      cue: editableTranscript.cues[1],
      audioPosition: const Duration(seconds: 14),
      offset: const Duration(seconds: -3),
      highlightedId: 2,
      audioDuration: const Duration(minutes: 2),
      recordedAt: DateTime.utc(2026, 11, 2),
    );
    measurements.samples.add(sample);
    expect(sample.rawDifference, const Duration(seconds: 4));
    expect(sample.residual, const Duration(seconds: 1));
    final report = jsonDecode(measurements.report(episode.title)) as Map;
    final row = (report['samples'] as List).single as Map;
    expect(row['observed_audio_start_ms'], 14000);
    expect(row['raw_difference_ms'], 4000);
    expect(row['calibrated_residual_ms'], 1000);
    expect(row['highlighted_passage_id'], 2);
    expect(
      diagnosticTime(const Duration(milliseconds: -1234), signed: true),
      '-00:00:01.234',
    );
  });

  testWidgets(
    'mark captures live clock without calibration or playback changes; reopening retains samples',
    (tester) async {
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      final store = MemoryTranscriptEditStore();
      addTearDown(player.dispose);
      await player.playEpisode(episode, from: const Duration(seconds: 4));
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            home: TranscriptPage(
              episode: episode,
              loadTranscript: (_) async => editableTranscript,
              editStore: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Transcript timing diagnostics'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('diagnostic-passage')),
        '2',
      );
      await player.seek(const Duration(seconds: 14));
      await tester.pumpAndSettle();
      final mark = find.byKey(const ValueKey('diagnostic-mark'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pumpAndSettle();
      expect(find.text('1 measurement'), findsOneWidget);
      expect(player.position, const Duration(seconds: 14));
      expect(player.playing, isTrue);
      expect(store.documents, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Transcript timing diagnostics'));
      await tester.pumpAndSettle();
      expect(find.text('1 measurement'), findsOneWidget);
      audio.buffering = true;
      player.refreshTranscriptEdit();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(mark).onPressed, isNull);
      audio.buffering = false;
      player.refreshTranscriptEdit();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(mark).onPressed, isNotNull);
      await player.toggle();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(mark).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('diagnostic-passage')),
        '999',
      );
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid passage number.'), findsOneWidget);
      await player.close();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(mark).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
