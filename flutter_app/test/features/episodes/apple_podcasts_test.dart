import 'dart:async';

import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/apple_podcasts.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/playback_preferences.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final episode = Episode(
    guid:
        'commondescentpodcast.podbean.com/6d9f44a3-05e4-3ca2-b8e8-32426a95678e',
    title: 'Plant Origins',
    number: '255',
    segments: const [
      Segment(
        sourceIndex: 0,
        guid: 'commondescentpodcast.podbean.com/6d9f44a3-05e4-3ca2-b8e8-32426a95678e',
        episodeTitle: 'Plant Origins',
        type: 'News',
        title: 'Mosasaurs',
        newsStartTime: Duration(minutes: 5, seconds: 25),
      ),
      Segment(
        sourceIndex: 1,
        guid: 'commondescentpodcast.podbean.com/6d9f44a3-05e4-3ca2-b8e8-32426a95678e',
        episodeTitle: 'Plant Origins',
        type: 'Main Discussion',
        title: 'Plant Origins',
        label: 'Main discussion, Part 1',
        startTime: Duration(minutes: 47, seconds: 35),
      ),
    ],
  );

  test('only an exact GUID match produces an episode link', () {
    final destination = ApplePodcasts.destinationFor(episode, {
      episode.guid: '1000797966828',
    });
    expect(destination.exact, isTrue);
    expect(destination.uri.host, 'podcasts.apple.com');
    expect(destination.uri.queryParameters['i'], '1000797966828');
    final missing = ApplePodcasts.destinationFor(episode, {});
    expect(missing.exact, isFalse);
    expect(missing.uri.queryParameters['term'], contains('Plant Origins'));
    expect(missing.uri.queryParameters.containsKey('i'), isFalse);
  });

  testWidgets(
    'episode button hands off and recovers',
    (tester) async {
      late PodcastDestination realDestination;
      await tester.runAsync(() async {
        realDestination = await ApplePodcasts.destination(episode);
      });
      expect(realDestination.exact, isTrue);
      expect(realDestination.uri.queryParameters['i'], '1000797966828');
      final destinationCompleter = Completer<PodcastDestination>();
      Uri? opened;
      final playback = PlaybackController(
        createEngine: () => throw StateError('Unexpected native audio'),
      );
      addTearDown(playback.dispose);
      await playback.setOutput(PlaybackOutput.applePodcasts);
      expect(playback.output, PlaybackOutput.applePodcasts);
      expect(playback.preferencesReady, isTrue);
      await tester.pumpWidget(
        PlaybackScope(
          controller: playback,
          child: MaterialApp(
            home: Scaffold(
              body: EpisodeDetail(
                episode: episode,
                loadPodcastDestination: (_) => destinationCompleter.future,
                openPodcastLink: (uri) async {
                  opened = uri;
                  return false;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final playButton = find.widgetWithText(FilledButton, 'Play');
      expect(tester.widget<FilledButton>(playButton).onPressed, isNull);
      destinationCompleter.complete(realDestination);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(playButton).onPressed, isNotNull);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(opened?.queryParameters['i'], '1000797966828');
      expect(find.text('Apple Podcasts could not be opened.'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    }),
  );
}
