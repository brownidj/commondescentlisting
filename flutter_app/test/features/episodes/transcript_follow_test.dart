import 'package:common_descent_listing/features/episodes/transcript_follow.dart';
import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio, episode;
import 'transcript_edit_test_support.dart';

class AdvancingAudio extends FakeAudio {
  void advanceTo(Duration time) {
    position = time;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'edit selection toggles without recalibrating audio and following resumes',
    (tester) async {
      final selected = episode(
        editableTranscript.episodeGuid,
        url: 'https://example.com/audio.mp3',
      );
      final store = MemoryTranscriptEditStore();
      final audio = AdvancingAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      await player.playEpisode(
        selected,
        from: const Duration(milliseconds: 9800),
      );
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            builder: (context, child) =>
                PlaybackLayout(controller: player, child: child!),
            home: TranscriptPage(
              episode: selected,
              editStore: store,
              loadTranscript: (_) async => editableTranscript,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey('transcript-cue-1'));
      final second = find.byKey(const ValueKey('transcript-cue-2'));
      expect(tester.widget<ListTile>(first).selected, isTrue);
      await tester.ensureVisible(second);
      await tester.longPress(second);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byTooltip('Edit passage 2'), findsOneWidget);
      expect(audio.position, const Duration(milliseconds: 9800));
      expect(store.documents, isEmpty);
      await tester.longPress(second);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Edit passage 2'), findsNothing);
      expect(audio.position, const Duration(milliseconds: 9800));
      audio.advanceTo(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(second).selected, isTrue);
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(seconds: 10));
      expect(store.documents, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'timing uses start-inclusive/end-exclusive boundaries and preserves gaps',
    () {
      final first = editableTranscript.cues.first;
      final second = editableTranscript.cues.last;
      expect(transcriptCueAt([first, second], Duration.zero)?.id, 1);
      expect(
        transcriptCueAt([first, second], const Duration(seconds: 10))?.id,
        2,
      );
      expect(
        transcriptCueAt([first, second], const Duration(seconds: 20)),
        isNull,
      );
      expect(transcriptCueAt([second], const Duration(seconds: 5)), isNull);
      expect(transcriptCueAt([], Duration.zero), isNull);
    },
  );

  testWidgets(
    'follow opening, distant seeks, scrolling, pause/resume and search',
    (tester) async {
      final selected = episode(
        'follow-test',
        url: 'https://example.com/audio.mp3',
      );
      final cues = List.generate(
        300,
        (index) => TranscriptCue(
          id: index + 1,
          start: Duration(seconds: index * 20),
          end: Duration(seconds: (index + 1) * 20),
          text: index == 10
              ? 'The needle passage.'
              : 'Passage $index. ${'Variable height text. ' * (index % 8 + 1)}',
          originalText: 'Original passage $index.',
          reviewNotes: [],
        ),
      );
      final transcript = EpisodeTranscript(
        episodeGuid: selected.guid,
        label: 'Reviewed transcript',
        note: 'Context review.',
        cues: cues,
      );
      final audio = AdvancingAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      await player.playEpisode(selected, from: const Duration(seconds: 4001));
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            home: TranscriptPage(
              episode: selected,
              editStore: MemoryTranscriptEditStore(),
              loadTranscript: (_) async => transcript,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void expectVisible(int cueId) {
        final target = find.byKey(ValueKey('transcript-cue-$cueId'));
        expect(target, findsOneWidget);
        expect(tester.widget<ListTile>(target).selected, isTrue);
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final tile = tester.getRect(target);
        expect(tile.top, greaterThanOrEqualTo(viewport.top - 1));
        expect(tile.top, lessThan(viewport.bottom));
      }

      expectVisible(201);
      expect(find.byType(ListTile).evaluate().length, lessThan(30));
      // Natural progress and both seek directions use the same time stream.
      audio.advanceTo(const Duration(seconds: 4021));
      await tester.pumpAndSettle();
      expectVisible(202);
      await player.seek(const Duration(seconds: 401));
      await tester.pumpAndSettle();
      expectVisible(21);
      await player.seek(const Duration(seconds: 5001));
      await tester.pumpAndSettle();
      expectVisible(251);
      // Manual scrolling cannot leave the current playing cue hidden.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expectVisible(251);
      final field = find.byType(TextField);
      await tester.enterText(field, 'needle');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('1 matching passage'), findsOneWidget);
      expect(
        find.textContaining('Also showing the playing passage'),
        findsOneWidget,
      );
      expectVisible(251);
      // Pausing restores normal search results and free reading.
      await player.toggle();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('transcript-cue-251')), findsNothing);
      expect(
        find.textContaining('Also showing the playing passage'),
        findsNothing,
      );
      await player.toggle();
      await tester.pumpAndSettle();
      expectVisible(251);
      await tester.tap(find.byTooltip('Clear transcript search'));
      await tester.pumpAndSettle();
      expectVisible(251);
      await player.toggle();
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        ),
      );
      scroll.position.jumpTo(scroll.position.pixels + 700);
      await tester.pumpAndSettle();
      final offset = scroll.position.pixels;
      audio.advanceTo(const Duration(seconds: 5021));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, offset);
      await player.toggle();
      await tester.pumpAndSettle();
      expectVisible(252);
      // Another episode must not drive this transcript's scrolling/highlighting.
      await player.playEpisode(
        episode('different', url: 'https://example.com/other.mp3'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('transcript-cue-252')))
            .selected,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
