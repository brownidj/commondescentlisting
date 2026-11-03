import 'dart:async';
import 'dart:io';

import 'package:common_descent_listing/data/bundled_transcripts.dart';
import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/playback_preferences.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

void main() {
  final episode = Episode(
    guid: BundledTranscripts.episode208Guid,
    title: 'The Karoo Supergroup',
    number: '208',
    segments: const [
      Segment(
        sourceIndex: 0,
        guid: BundledTranscripts.episode208Guid,
        episodeTitle: 'The Karoo Supergroup',
        type: 'Episode',
        audioUrl: 'https://example.com/episode208.mp3',
      ),
    ],
  );

  for (final alreadyPlaying in [false, true]) {
    testWidgets(
      'index deep link focuses and highlights requested passage (playing: $alreadyPlaying)',
      (tester) async {
        final audio = FakeAudio();
        final player = PlaybackController(createEngine: () => audio);
        addTearDown(player.dispose);
        if (alreadyPlaying) {
          await player.playEpisode(episode, from: const Duration(seconds: 3));
        }
        final originalPosition = audio.position;
        final transcript = EpisodeTranscript(
          episodeGuid: episode.guid,
          label: 'Test',
          note: '',
          cues: [
            for (var i = 1; i <= 100; i++)
              TranscriptCue(
                id: i,
                start: Duration(seconds: i * 2),
                end: Duration(seconds: i * 2 + 1),
                text: 'Passage content $i',
                originalText: 'Passage content $i',
                reviewNotes: const [],
              ),
          ],
        );
        await tester.pumpWidget(
          PlaybackScope(
            controller: player,
            child: MaterialApp(
              home: TranscriptPage(
                episode: episode,
                initialPassageId: 80,
                editStore: MemoryTranscriptEditStore(),
                loadTranscript: (_) async => transcript,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('transcript-cue-80')), findsOneWidget);
        expect(find.text('Opened passage 80'), findsOneWidget);
        final tile = tester.widget<ListTile>(
          find.byKey(const ValueKey('transcript-cue-80')),
        );
        expect(tile.selected, isTrue);
        expect(find.byTooltip('Edit passage 80'), findsNothing);
        expect(audio.playing, alreadyPlaying);
        expect(audio.position, originalPosition);
        if (alreadyPlaying) {
          audio.position = const Duration(seconds: 10);
          audio.notifyListeners();
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ListTile>(
                  find.byKey(const ValueKey('transcript-cue-80')),
                )
                .selected,
            isTrue,
          );
          await tester.tap(find.text('Follow audio'));
          await tester.pumpAndSettle();
          expect(find.text('Opened passage 80'), findsNothing);
          expect(audio.playing, isTrue);
          expect(audio.position, const Duration(seconds: 10));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('reviewed/original text and timed playback share one player', (
    tester,
  ) async {
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    final source = File('assets/transcripts/episode-208-karoo-reviewed.json')
        .readAsStringSync();
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          home: TranscriptPage(
            editStore: MemoryTranscriptEditStore(),
            episode: episode,
            loadTranscript: (guid) async =>
                EpisodeTranscript.parse(source, episodeGuid: guid),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Machine transcribed; names and terminology reviewed.'),
      findsOneWidget,
    );
    expect(
      find.text("You're listening to the Common Descent podcast."),
      findsOneWidget,
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      find.text("You're listening to the Common Dissent podcast."),
      findsOneWidget,
    );
    final secondCue = find.byKey(const ValueKey('transcript-cue-2'));
    await tester.ensureVisible(secondCue);
    await tester.tap(secondCue);
    await tester.pumpAndSettle();
    expect(player.episode?.guid, episode.guid);
    expect(audio.position, const Duration(milliseconds: 19760));
    expect(audio.playing, isTrue);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('transcript-cue-2')))
          .selected,
      isTrue,
    );
    await player.setOutput(PlaybackOutput.applePodcasts);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('transcript-cue-2')))
          .onTap,
      isNull,
    );
    expect(audio.playing, isFalse);
  });

  testWidgets('failed transcript load remains retryable', (tester) async {
    final source = File('assets/transcripts/episode-208-karoo-reviewed.json')
        .readAsStringSync();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TranscriptPage(
          editStore: MemoryTranscriptEditStore(),
          episode: episode,
          loadTranscript: (guid) async {
            attempts++;
            if (attempts == 1) {
              throw const FormatException('Unavailable asset');
            }
            return EpisodeTranscript.parse(source, episodeGuid: guid);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The transcript could not be loaded.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode replacement resets search and ignores stale loads', (
    tester,
  ) async {
    final secondEpisode = Episode(
      guid: 'episode-second',
      title: 'Second episode',
      number: '209',
      segments: [],
    );
    final thirdEpisode = Episode(
      guid: 'episode-third',
      title: 'Third episode',
      number: '210',
      segments: [],
    );
    EpisodeTranscript transcript(String guid, String title) =>
        EpisodeTranscript(
          episodeGuid: guid,
          label: 'Transcript: $title',
          note: '',
          cues: [
            TranscriptCue(
              id: 1,
              start: Duration.zero,
              end: const Duration(seconds: 10),
              text: title,
              originalText: title,
              reviewNotes: const [],
            ),
          ],
        );
    final secondLoad = Completer<EpisodeTranscript>();
    final store = MemoryTranscriptEditStore();
    Future<EpisodeTranscript> load(String guid) {
      if (guid == episode.guid) {
        return Future.value(transcript(guid, 'First episode passage'));
      }
      if (guid == secondEpisode.guid) return secondLoad.future;
      return Future.value(transcript(guid, 'Third episode passage'));
    }

    Widget page(Episode selectedEpisode) => MaterialApp(
      home: TranscriptPage(
        episode: selectedEpisode,
        editStore: store,
        loadTranscript: load,
      ),
    );

    await tester.pumpWidget(page(episode));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.enterText(search, 'First episode');
    await tester.pumpAndSettle();
    expect(find.text('1 matching passage'), findsOneWidget);

    await tester.pumpWidget(page(secondEpisode));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('First episode passage'), findsNothing);
    await tester.pumpWidget(page(thirdEpisode));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('Third episode passage'), findsOneWidget);
    expect(find.text('First episode passage'), findsNothing);

    secondLoad.complete(transcript(secondEpisode.guid, 'Stale second passage'));
    await tester.pumpAndSettle();
    expect(find.text('Third episode passage'), findsOneWidget);
    expect(find.text('Stale second passage'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export warns that subtitle timings remain original', (
    tester,
  ) async {
    var exported = false;
    await tester.pumpWidget(
      MaterialApp(
        home: TranscriptPage(
          editStore: MemoryTranscriptEditStore(),
          episode: episode,
          loadTranscript: (_) async => EpisodeTranscript(
            episodeGuid: episode.guid,
            label: 'Reviewed transcript',
            note: '',
            cues: const [],
          ),
          exportTranscript: (_) async {
            exported = true;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final exportButton = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == 'Export reviewed transcript',
    );
    expect(tester.widget<IconButton>(exportButton).onPressed, isNotNull);
    await tester.tap(exportButton);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('VTT and SRT keep the original passage timestamps.'),
      findsOneWidget,
    );
    expect(find.textContaining('Only the JSON export'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(exported, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'search filters passages, switches wording and preserves seek time',
    (tester) async {
      const transcript = EpisodeTranscript(
        episodeGuid: BundledTranscripts.episode208Guid,
        label: 'Reviewed transcript',
        note: 'Context review only.',
        cues: [
          TranscriptCue(
            id: 1,
            start: Duration.zero,
            end: Duration(seconds: 20),
            text: 'Opening remarks.',
            originalText: 'Opening remarks.',
            reviewNotes: [],
          ),
          TranscriptCue(
            id: 20,
            start: Duration(minutes: 40),
            end: Duration(minutes: 41),
            text: 'Karoo fossils and Karoo rocks.',
            originalText: 'Karu fossils and Karu rocks.',
            reviewNotes: ['Check the audio.'],
          ),
        ],
      );
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            home: TranscriptPage(
              editStore: MemoryTranscriptEditStore(),
              episode: episode,
              loadTranscript: (_) async => transcript,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.enterText(field, '  kArOo  ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('1 matching passage'), findsOneWidget);
      expect(find.byKey(const ValueKey('transcript-cue-1')), findsNothing);
      final match = find.byKey(const ValueKey('transcript-cue-20'));
      await tester.ensureVisible(match);
      final tile = tester.widget<ListTile>(match);
      expect(
        (tile.title! as Text).textSpan!.toPlainText(),
        'Karoo fossils and Karoo rocks.',
      );
      expect(find.text('Needs review: Check the audio.'), findsOneWidget);
      await tester.tap(match);
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(minutes: 40));
      expect(audio.playing, isTrue);
      // Playback follows its passage; pause before browsing back to the header.
      await player.toggle();
      await tester.pumpAndSettle();
      final mode = find.byType(SwitchListTile);
      await tester.ensureVisible(mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(find.text('No matching passages'), findsOneWidget);
      expect(match, findsNothing);
      await tester.enterText(field, 'Karu');
      await tester.pumpAndSettle();
      expect(find.text('1 matching passage'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear transcript search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transcript-cue-1')), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(find.text('1 matching passage'), findsNothing);
      expect(audio.position, const Duration(minutes: 40));
      expect(tester.takeException(), isNull);
    },
  );
}
