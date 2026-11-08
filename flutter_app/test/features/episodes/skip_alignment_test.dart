import 'dart:convert';

import 'package:common_descent_listing/data/episode_audio.dart';
import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/playback_audio_source.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'playback_controller_test.dart' show FakeAudio, episode;
import 'transcript_edit_test_support.dart';

class _ProgressAudio extends FakeAudio {
  void advanceTo(Duration value) {
    position = value;
    notifyListeners();
  }
}

void main() {
  test('fixed asset requests precise Apple timing; streaming format detection stays intact', () {
    final asset = Uri(scheme: 'asset', path: '/${EpisodeAudio.karooAsset}');
    final source = playbackAudioSource(asset) as ProgressiveAudioSource;
    expect(source.uri, asset);
    expect(
      source.options?.darwinAssetOptions?.preferPreciseDurationAndTiming,
      isTrue,
    );
    expect(
      playbackAudioSource(Uri.parse('https://example.com/live.m3u8')),
      isA<HlsAudioSource>(),
    );
  });

  test('only successful explicit seeks change the seek revision', () async {
    final audio = _ProgressAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    await player.playEpisode(
      episode('skip', url: 'https://example.com/audio.mp3'),
    );
    final revision = player.seekRevision;
    audio.advanceTo(const Duration(seconds: 10));
    expect(player.seekRevision, revision);
    await player.skip(const Duration(seconds: 30));
    expect(player.seekRevision, revision + 1);
    expect(player.position, const Duration(seconds: 40));
    audio.failSeek = true;
    await player.skip(const Duration(seconds: 30));
    expect(player.seekRevision, revision + 1);
    expect(player.position, const Duration(seconds: 40));
  });

  testWidgets(
    'forward/back skip follows the new passage, clears held selection and preserves saved Nudge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      final selected = episode(
        EpisodeAudio.karooGuid,
        url: 'https://example.com/episode.mp3',
      );
      final store = MemoryTranscriptEditStore();
      final cues = List.generate(
        100,
        (i) => TranscriptCue(
          id: i + 1,
          start: Duration(seconds: i * 5),
          end: Duration(seconds: (i + 1) * 5),
          text: 'Passage ${i + 1} words.',
          originalText: 'Passage ${i + 1} words.',
          reviewNotes: const [],
        ),
      );
      final transcript = EpisodeTranscript(
        episodeGuid: selected.guid,
        label: 'Aligned transcript',
        note: '',
        cues: cues,
        audioIdentity: EpisodeAudio.karooIdentity,
      );
      final edits = TranscriptEdits(baseline: transcript, store: store);
      await edits.load();
      await edits.setSyncOffset(const Duration(milliseconds: 500));
      edits.dispose();
      await player.playEpisode(selected, from: const Duration(seconds: 1));
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            builder: (context, child) =>
                PlaybackLayout(controller: player, child: child!),
            home: TranscriptPage(
              episode: selected,
              editStore: store,
              loadTranscript: (_) async => transcript,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final journal = store.documents[selected.guid];
      expect(jsonDecode(journal!)['sync_offset_ms'], 500);
      final second = find.byKey(const ValueKey('transcript-cue-2'));
      await tester.ensureVisible(second);
      await tester.tap(second, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit passage 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Forward 30 seconds'));
      await tester.pumpAndSettle();
      void expectFollowing(int id) {
        expect(find.text('Passage $id of 100'), findsOneWidget);
        final tile = find.byKey(ValueKey('transcript-cue-$id'));
        expect(tile, findsOneWidget);
        expect(tester.widget<ListTile>(tile).selected, isTrue);
        final viewport = tester.getRect(find.byType(CustomScrollView));
        expect(
          tester.getRect(tile).top,
          greaterThanOrEqualTo(viewport.top - 1),
        );
        expect(
          tester.getRect(tile).bottom,
          lessThanOrEqualTo(viewport.bottom + 1),
        );
        expect(store.documents[selected.guid], journal);
        expect(audio.source?.scheme, 'asset');
        expect(audio.playing, isTrue);
      }

      expect(find.byTooltip('Edit passage 2'), findsNothing);
      expect(player.position, const Duration(seconds: 31));
      expectFollowing(7);
      await tester.tap(find.byTooltip('Forward 30 seconds'));
      await tester.pumpAndSettle();
      expectFollowing(13);
      await tester.tap(find.byTooltip('Back 15 seconds'));
      await tester.pumpAndSettle();
      expectFollowing(10);
      expect(audio.loads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
