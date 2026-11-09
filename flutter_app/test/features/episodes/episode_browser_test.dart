import 'package:common_descent_listing/features/episodes/episode_browser.dart';
import 'package:common_descent_listing/features/episodes/episode_controller.dart';
import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/data/bundled_transcripts.dart';
import 'package:common_descent_listing/data/local_prepared_episodes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Catalogue fixture() {
  final segments = [
    const Segment(
      sourceIndex: 0,
      guid: 'main',
      episodeTitle: 'Shared title',
      episodeNumber: '37.5',
      type: 'News',
      title: 'Plants',
      needsReview: true,
      newsRaw: 'Plants, and birds.',
      newsStartTime: Duration(minutes: 5),
      sourceUrl: 'https://example.com/episode',
    ),
    const Segment(
      sourceIndex: 1,
      guid: 'main',
      episodeTitle: 'Shared title',
      episodeNumber: '37.5',
      type: 'Main Discussion',
      title: 'Plants',
      label: 'Main discussion, Part 1',
      startTime: Duration.zero,
    ),
    const Segment(
      sourceIndex: 2,
      guid: 'main',
      episodeTitle: 'Shared title',
      episodeNumber: '37.5',
      type: 'Main Discussion',
      title: 'Plants',
      label: 'Main discussion, Part 2',
      startTime: Duration(hours: 1, minutes: 2),
    ),
    const Segment(
      sourceIndex: 3,
      guid: 'side',
      episodeTitle: 'Shared title',
      type: 'Episode',
      sourceUrl: 'javascript:alert(1)',
    ),
  ];
  return Catalogue(
    podcast: const Podcast(title: 'Podcast'),
    sourceName: 'fixture',
    segments: segments,
    episodes: [
      Episode(
        guid: 'main',
        title: 'Shared title',
        number: '37.5',
        segments: segments.take(3),
      ),
      Episode(
        guid: 'side',
        title: 'Shared title',
        number: null,
        segments: segments.skip(3),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'transcript markers reflect bundled and newly prepared episodes',
    (tester) async {
      LocalPreparedEpisodes.replace([]);
      addTearDown(() => LocalPreparedEpisodes.replace([]));
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = fixture();
      final bundled = Episode(
        guid: BundledTranscripts.episode208Guid,
        title: 'The Karoo Supergroup',
        number: '208',
        segments: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodeBrowser(
              catalogue: Catalogue(
                podcast: data.podcast,
                segments: data.segments,
                episodes: [...data.episodes, bundled],
                sourceName: 'fixture',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder marker(String guid) => find.descendant(
        of: find.byKey(ValueKey('episode-$guid')),
        matching: find.byTooltip('Transcript available'),
      );
      expect(marker(bundled.guid), findsOneWidget);
      expect(marker('main'), findsNothing);
      expect(marker('side'), findsNothing);
      expect(find.text('Episode 37.5 • 1 news records'), findsOneWidget);
      final transcribed = find.widgetWithText(ChoiceChip, 'Transcribed');
      await tester.ensureVisible(transcribed);
      await tester.tap(transcribed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('episode-main')), findsNothing);
      expect(find.byKey(const ValueKey('episode-side')), findsNothing);
      expect(marker(bundled.guid), findsOneWidget);
      LocalPreparedEpisodes.replace([
        LocalPreparedEdition(
          guid: 'main',
          edition: 'new',
          audioUri: Uri.parse('http://127.0.0.1/audio.opus'),
          audioIdentity: 'sha256:test',
          duration: const Duration(seconds: 5),
          passageCount: 1,
          loadText: (_) async =>
              throw StateError('Listing must not load transcript'),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(marker('main'), findsOneWidget);
      expect(find.byKey(const ValueKey('episode-main')), findsOneWidget);
      expect(marker('side'), findsNothing);
      LocalPreparedEpisodes.replace([]);
      await tester.pumpAndSettle();
      expect(marker('main'), findsNothing);
      expect(find.byKey(const ValueKey('episode-main')), findsNothing);
      expect(marker(bundled.guid), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('enlarged text keeps a short narrow episode list scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: EpisodeBrowser(catalogue: fixture())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('episode-side')),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('episode-side'))),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('episode-side')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EpisodeDetail>(find.byType(EpisodeDetail)).episode.guid,
      'side',
    );
    expect(find.text('Side episode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('legacy undated filters/search preserve source order and fractional numbers', () {
    final controller = EpisodeController(fixture().episodes);
    addTearDown(controller.dispose);
    controller.setQuery('  SHARED  ');
    expect(controller.visibleEpisodes.map((e) => e.guid), ['main', 'side']);
    controller.setFilter(EpisodeFilter.side);
    expect(controller.visibleEpisodes.single.guid, 'side');
    controller.setFilter(EpisodeFilter.numbered);
    controller.setQuery('37.5');
    expect(controller.visibleEpisodes.single.guid, 'main');
    controller.setQuery('unmatched');
    expect(controller.visibleEpisodes, isEmpty);
    controller.setQuery('');
    controller.setFilter(EpisodeFilter.all);
    expect(controller.visibleEpisodes.map((e) => e.guid), ['main', 'side']);
  });

  testWidgets(
    'narrow selection opens the correct GUID and back retains search',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EpisodeBrowser(catalogue: fixture())),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('episode-title-search')),
        'shared',
      );
      await tester.tap(find.byKey(const ValueKey('episode-side')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EpisodeDetail>(find.byType(EpisodeDetail)).episode.guid,
        'side',
      );
      expect(find.text('Episode page unavailable'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Episode'), findsNothing);
      await tester.tap(find.text('Back to episodes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('episode-title-search')),
            )
            .controller!
            .text,
        'shared',
      );
      expect(find.byKey(const ValueKey('episode-main')), findsOneWidget);
    },
  );

  testWidgets(
    'wide selection shows list/detail and keeps selection when resized',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1300, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EpisodeBrowser(catalogue: fixture())),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('episode-main')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<EpisodeDetail>(find.byType(EpisodeDetail)).episode.guid,
        'main',
      );
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      await tester.pumpAndSettle();
      expect(find.text('Back to episodes'), findsOneWidget);
      expect(
        tester.widget<EpisodeDetail>(find.byType(EpisodeDetail)).episode.guid,
        'main',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'detail distinguishes news-section times and separate discussion parts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodeDetail(episode: fixture().episodes.first),
          ),
        ),
      );
      expect(find.text('Item time unavailable'), findsNothing);
      expect(find.text('- starts at 00:05:00'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('segment-main::0')),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('segment-main::0')),
          matching: find.text('- starts at 00:05:00'),
        ),
        findsNothing,
      );
      expect(find.text('Starts at 00:05:00'), findsNothing);
      expect(find.text('Main discussion'), findsOneWidget);
      expect(find.text('Main Discussion'), findsNothing);
      expect(find.text('Plants - Part 1'), findsOneWidget);
      expect(find.text('Plants - Part 2'), findsOneWidget);
      expect(find.text('Starts at 00:00:00'), findsOneWidget);
      expect(find.text('Starts at 01:02:00'), findsOneWidget);
      expect(find.text('Episode 37.5'), findsOneWidget);
      const notice =
          'News headlines were split automatically and may need review. '
          'Open the episode page for context.';
      expect(find.text(notice), findsNothing);
      expect(find.byTooltip(notice), findsOneWidget);
      expect(find.text('Original news summary'), findsNothing);
      expect(find.text('Plants, and birds.'), findsNothing);
    },
  );

  testWidgets(
    'valid source URL opens via injected external opener; failure is recoverable',
    (tester) async {
      Uri? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodeDetail(
              episode: fixture().episodes.first,
              openLink: (uri) async {
                opened = uri;
                return false;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Episode'));
      await tester.pumpAndSettle();
      expect(opened.toString(), 'https://example.com/episode');
      expect(
        find.text('The episode page could not be opened. Please try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty catalogue and unmatched search are distinct', (
    tester,
  ) async {
    final empty = Catalogue(
      podcast: const Podcast(title: 'Podcast'),
      segments: [],
      episodes: [],
      sourceName: 'empty',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EpisodeBrowser(catalogue: empty)),
      ),
    );
    expect(find.text('The catalogue is empty'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EpisodeBrowser(catalogue: fixture())),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('episode-title-search')),
      'nothing matches',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching episodes'), findsOneWidget);
  });
}
