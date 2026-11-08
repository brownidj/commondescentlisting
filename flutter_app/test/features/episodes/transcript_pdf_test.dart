import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:common_descent_listing/widgets/playback_route_observer.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

void main() {
  testWidgets(
    'PDF exports all saved text without timing and hides outside reader',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final episode = Episode(
        guid: editableTranscript.episodeGuid,
        title: 'Episode',
        number: '208',
        segments: [
          Segment(
            sourceIndex: 0,
            guid: editableTranscript.episodeGuid,
            episodeTitle: 'Episode',
            type: 'Episode',
            audioUrl: 'https://example.com/audio.mp3',
          ),
        ],
      );
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      final store = MemoryTranscriptEditStore();
      addTearDown(player.dispose);
      await player.playEpisode(
        episode,
        from: const Duration(milliseconds: 9800),
      );
      String? exportedGuid;
      List<String>? exportedPassages;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [playbackRouteObserver],
            builder: (context, child) =>
                PlaybackLayout(controller: player, child: child!),
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('player-create-pdf'));
      expect(button, findsNothing);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TranscriptPage(
            episode: episode,
            editStore: store,
            exportPdf: (guid, passages) async {
              exportedGuid = guid;
              exportedPassages = passages;
              return '/project/docs/transcripts/episode.pdf';
            },
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nudge'), findsNothing);
      expect(find.text('Create .pdf'), findsOneWidget);
      final passage = find.byKey(const ValueKey('player-current-passage'));
      expect(
        (tester.getCenter(button).dy - tester.getCenter(passage).dy).abs(),
        lessThan(1),
      );
      await tester.enterText(find.byType(TextField).first, 'no matching passage');
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(exportedGuid, episode.guid);
      expect(exportedPassages, editableTranscript.cues.map((cue) => cue.text).toList());
      expect(player.position, const Duration(milliseconds: 9800));
      expect(player.playing, isTrue);
      expect(store.documents, isEmpty);
      expect(find.text('PDF saved to /project/docs/transcripts/episode.pdf'), findsOneWidget);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(button, findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
