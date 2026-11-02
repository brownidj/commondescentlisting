import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

void main() {
  testWidgets(
    'player pins icon-only Edit, resolves current highlight and cleans up after leaving',
    (tester) async {
      final selected = Episode(
        guid: editableTranscript.episodeGuid,
        title: 'Episode',
        number: '208',
        segments: [
          Segment(
            sourceIndex: 0,
            guid: editableTranscript.episodeGuid,
            episodeTitle: 'Episode',
            type: 'Main Discussion',
            title: 'Discussion',
            startTime: Duration.zero,
            audioUrl: 'https://example.com/audio.mp3',
          ),
        ],
      );
      final player = PlaybackController(createEngine: FakeAudio.new);
      addTearDown(player.dispose);
      player.selectEpisode(selected);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) =>
                PlaybackLayout(controller: player, child: child!),
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TranscriptPage(
                          episode: selected,
                          editStore: MemoryTranscriptEditStore(),
                          loadTranscript: (_) async => editableTranscript,
                        ),
                      ),
                    ),
                    child: const Text('Open reader'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open reader'));
      await tester.pumpAndSettle();
      final sync = find.byKey(const ValueKey('player-transcript-edit'));
      final bar = find.byType(PlaybackBar);
      expect(find.descendant(of: bar, matching: sync), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AppBar), matching: sync),
        findsNothing,
      );
      final chip = find.byType(ChoiceChip);
      expect(tester.getCenter(sync).dx, greaterThan(tester.getCenter(chip).dx));
      expect(
        (tester.getCenter(sync).dy - tester.getCenter(chip).dy).abs(),
        lessThan(12),
      );
      expect(
        tester.getRect(sync).right,
        greaterThan(tester.getRect(bar).right - 20),
      );
      await tester.tap(sync);
      await tester.pumpAndSettle();
      expect(find.text('Edit passage 1'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('player-transcript-sync')),
        findsNothing,
      );
      await tester.tap(find.text('Cancel'));
      await player.seek(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.tap(sync);
      await tester.pumpAndSettle();
      expect(find.text('Edit passage 2'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // Keep the control pinned while the segment area scrolls on a phone width.
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(sync).right,
        greaterThan(tester.getRect(bar).right - 20),
      );
      expect(tester.takeException(), isNull);
      // A different selected episode must not adjust this reader's timing.
      await player.close();
      player.selectEpisode(
        Episode(
          guid: 'other',
          title: 'Other',
          number: null,
          segments: const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(sync).onPressed, isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(sync, findsNothing);
    },
  );
}
