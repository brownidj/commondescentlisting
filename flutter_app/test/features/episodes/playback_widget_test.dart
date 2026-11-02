import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;

void main() {
  testWidgets(
    'segment actions seek in-app and the player survives navigation',
    (tester) async {
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      final episode = Episode(
        guid: 'plants',
        title: 'Plant Origins',
        number: '255',
        segments: const [
          Segment(
            sourceIndex: 0,
            guid: 'plants',
            episodeTitle: 'Plant Origins',
            type: 'News',
            title: 'Mosasaurs',
            audioUrl: 'https://example.com/plants.mp3',
            newsStartTime: Duration(minutes: 5, seconds: 25),
          ),
          Segment(
            sourceIndex: 1,
            guid: 'plants',
            episodeTitle: 'Plant Origins',
            type: 'Main Discussion',
            title: 'Plant Origins',
            label: 'Main discussion, Part 1',
            startTime: Duration(minutes: 47, seconds: 35),
          ),
        ],
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(body: EpisodeDetail(episode: episode)),
            builder: (context, child) =>
                PlaybackLayout(controller: player, child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlaybackBar), findsOneWidget);
      expect(player.episode?.guid, 'plants');
      expect(audio.loads, 0);
      final previewNews = find.widgetWithText(ChoiceChip, 'News');
      expect(previewNews, findsOneWidget);
      await tester.tap(previewNews);
      await tester.pumpAndSettle();
      expect(player.position.inSeconds, 325);
      expect(audio.loads, 1);
      expect(audio.playing, isTrue);
      Future<void> revealSegment(Finder target, double delta) async {
        final detailsScroll = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        // ListView may not have built a segment beyond its cache yet.
        await tester.scrollUntilVisible(
          target,
          delta,
          scrollable: detailsScroll,
        );
        await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
        await tester.pumpAndSettle();
      }

      final discussion = find.text('Starts at 00:47:35');
      await revealSegment(discussion, 150);
      await tester.tap(discussion);
      await tester.pumpAndSettle();
      expect(audio.position.inSeconds, 2855);
      expect(audio.playing, isTrue);
      expect(tester.takeException(), isNull);
      final pauseTooltip = tester.state<RawTooltipState>(
        find.byTooltip('Pause'),
      );
      pauseTooltip.ensureTooltipVisible();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('Pause'), findsOneWidget);
      Tooltip.dismissAllToolTips();
      await tester.pumpAndSettle();
      final news = find.text('News section starts at 00:05:25');
      await revealSegment(news, -150);
      await tester.tap(news);
      await tester.pumpAndSettle();
      expect(audio.position.inSeconds, 325);
      expect(audio.loads, 1);
      final newsChapter = find.widgetWithText(ChoiceChip, 'News');
      expect(newsChapter, findsOneWidget);
      final selectedChapter = tester.widget<ChoiceChip>(newsChapter);
      expect(selectedChapter.selected, isTrue);
      final partChapter = find.widgetWithText(
        ChoiceChip,
        'Plant Origins - Part 1',
      );
      await tester.ensureVisible(partChapter);
      await tester.tap(partChapter);
      await tester.pumpAndSettle();
      expect(audio.position.inSeconds, 2855);
      await tester.ensureVisible(newsChapter);
      await tester.tap(newsChapter);
      await tester.pumpAndSettle();
      expect(audio.position.inSeconds, 325);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
      await tester.tap(find.byTooltip('Play'));
      await tester.pumpAndSettle();
      expect(audio.playing, isTrue);
      expect(audio.position.inSeconds, 325);
      await tester.tap(find.byTooltip('Close player'));
      await tester.pumpAndSettle();
      expect(player.episode, isNull);
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.text('Select an episode to play'), findsOneWidget);
    },
  );
}
