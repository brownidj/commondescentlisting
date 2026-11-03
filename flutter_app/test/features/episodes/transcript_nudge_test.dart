import 'dart:convert';

import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:common_descent_listing/widgets/playback_route_observer.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

void main() {
  testWidgets(
    'transcript nudges save 500 ms steps without moving audio and hide outside reader',
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
      final back = find.byKey(const ValueKey('player-nudge-back'));
      final forward = find.byKey(const ValueKey('player-nudge-forward'));
      expect(forward, findsNothing);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => TranscriptPage(
            episode: episode,
            editStore: store,
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nudge'), findsOneWidget);
      final passage = find.byKey(const ValueKey('player-current-passage'));
      expect(
        (tester.getCenter(forward).dy - tester.getCenter(passage).dy).abs(),
        lessThan(1),
      );
      expect(find.text('Passage 1 of 2'), findsOneWidget);
      await tester.tap(forward);
      await tester.pumpAndSettle();
      expect(player.currentPassage?.id, 2);
      expect(jsonDecode(store.documents[episode.guid]!)['sync_offset_ms'], 500);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(player.currentPassage?.id, 1);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(
        jsonDecode(store.documents[episode.guid]!)['sync_offset_ms'],
        -500,
      );
      expect(player.position, const Duration(milliseconds: 9800));
      expect(player.playing, isTrue);
      final reopened = TranscriptEdits(
        baseline: editableTranscript,
        store: store,
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.syncOffset, const Duration(milliseconds: -500));
      expect(reopened.history, isEmpty);
      store.failSave = true;
      await tester.tap(forward);
      await tester.pumpAndSettle();
      expect(
        jsonDecode(store.documents[episode.guid]!)['sync_offset_ms'],
        -500,
      );
      expect(
        find.text('The timing nudge could not be saved. Please try again.'),
        findsOneWidget,
      );
      store.failSave = false;
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Other page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(forward, findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(forward, findsOneWidget);
      await player.close();
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(forward).onPressed, isNull);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(forward, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
