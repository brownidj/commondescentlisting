import 'package:common_descent_listing/features/episodes/episode_controller.dart';
import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/features/news/news_browser.dart';
import 'package:common_descent_listing/features/news/news_controller.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Catalogue fixture({bool noNews = false}) {
  final segments = [
    const Segment(
      sourceIndex: 0,
      guid: 'a',
      episodeTitle: 'Plants',
      episodeNumber: '37.5',
      type: 'News',
      title: 'Repeated headline',
      newsStartTime: Duration(minutes: 5),
      newsRaw: 'Repeated headline, and fossils.',
      needsReview: true,
    ),
    const Segment(
      sourceIndex: 1,
      guid: 'a',
      episodeTitle: 'Plants',
      episodeNumber: '37.5',
      type: 'News',
      title: 'Repeated headline',
      newsRaw: 'Repeated headline, and fossils.',
      needsReview: true,
    ),
    const Segment(
      sourceIndex: 2,
      guid: 'b',
      episodeTitle: 'Animals',
      episodeNumber: '18A',
      type: 'News',
      title: 'Repeated headline',
    ),
    const Segment(
      sourceIndex: 3,
      guid: 'side',
      episodeTitle: 'Special',
      type: 'News',
      title: null,
    ),
    const Segment(
      sourceIndex: 4,
      guid: 'a',
      episodeTitle: 'Plants',
      episodeNumber: '37.5',
      type: 'Main Discussion',
      title: 'Plants',
    ),
  ];
  final data = noNews ? segments.where((s) => !s.isNews).toList() : segments;
  final guids = data.map((s) => s.guid).toSet();
  return Catalogue(
    podcast: const Podcast(title: 'Podcast'),
    sourceName: 'fixture',
    segments: data,
    episodes: [
      for (final guid in guids)
        Episode(
          guid: guid,
          title: data.firstWhere((s) => s.guid == guid).episodeTitle,
          number: data.firstWhere((s) => s.guid == guid).episodeNumber,
          segments: data.where((s) => s.guid == guid),
        ),
    ],
  );
}

void main() {
  test('news search retains duplicates, source order, and episode context', () {
    final data = fixture();
    final news = NewsController(data);
    final episodes = EpisodeController(data.episodes);
    addTearDown(news.dispose);
    addTearDown(episodes.dispose);
    news.setQuery('  REPEATED  ');
    expect(news.visibleEntries.map((e) => e.segment.sourceIndex), [0, 1, 2]);
    expect(news.visibleEntries.map((e) => e.episode.guid), ['a', 'a', 'b']);
    for (final query in ['  PLANTS ', '37.5', ' 18a ']) {
      news.setQuery(query);
      episodes.setQuery(query);
      expect(
        news.visibleEntries.map((e) => e.episode.guid).toSet(),
        episodes.visibleEpisodes.map((e) => e.guid).toSet(),
      );
    }
    news.setQuery('no matches');
    expect(news.visibleEntries, isEmpty);
    news.setQuery('');
    expect(news.visibleEntries.map((e) => e.segment.sourceIndex), [0, 1, 2, 3]);
    expect(news.entries.map((e) => e.segment.sessionId).toSet(), hasLength(4));
  });

  testWidgets(
    'duplicate headline opens exact GUID/item and Back retains search',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NewsBrowser(catalogue: fixture())),
        ),
      );
      await tester.enterText(find.byType(TextField), ' REPEATED ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('news-a::1')));
      await tester.pumpAndSettle();
      final detail = tester.widget<EpisodeDetail>(find.byType(EpisodeDetail));
      expect(detail.episode.guid, 'a');
      expect(detail.selectedSegmentId, 'a::1');
      expect(find.text('News item 2 of 2'), findsOneWidget);
      await tester.tap(find.text('Selected item original summary'));
      await tester.pumpAndSettle();
      expect(find.text('Repeated headline, and fossils.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ' REPEATED ',
      );
      await tester.tap(find.byKey(const ValueKey('news-b::2')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EpisodeDetail>(find.byType(EpisodeDetail)).episode.guid,
        'b',
      );
    },
  );

  testWidgets(
    'news times, untitled fallback and clear search retain correct meanings',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NewsBrowser(catalogue: fixture())),
        ),
      );
      expect(find.text('News section starts at 00:05:00'), findsOneWidget);
      expect(find.text('Item starts at 00:05:00'), findsNothing);
      expect(find.text('News section'), findsOneWidget);
      expect(find.text('Side episode • Special'), findsOneWidget);
      expect(
        find.text(
          'Automatic headline split or incomplete data — check original summary',
        ),
        findsNWidgets(2),
      );
      await tester.enterText(find.byType(TextField), '18A');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('news-b::2')), findsOneWidget);
      expect(find.byKey(const ValueKey('news-a::0')), findsNothing);
      await tester.tap(find.byTooltip('Clear news search'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(4));
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .map((tile) => tile.key),
        [
          const ValueKey('news-a::0'),
          const ValueKey('news-a::1'),
          const ValueKey('news-b::2'),
          const ValueKey('news-side::3'),
        ],
      );
    },
  );

  testWidgets('news tile classifies its own episode number', (tester) async {
    const segment = Segment(
      sourceIndex: 0,
      guid: 'mismatch',
      episodeTitle: 'Number mismatch',
      episodeNumber: '  ',
      type: 'News',
      needsReview: false,
      headlineSplitMethod: 'automatic',
    );
    final catalogue = Catalogue(
      podcast: const Podcast(title: 'Podcast'),
      sourceName: 'fixture',
      segments: const [segment],
      episodes: [
        Episode(
          guid: 'mismatch',
          title: 'Number mismatch',
          number: '41',
          segments: const [segment],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: NewsBrowser(catalogue: catalogue))),
    );

    expect(find.text('Side episode • Number mismatch'), findsOneWidget);
    expect(find.text('Episode 41 • Number mismatch'), findsNothing);
    expect(
      find.text(
        'Automatic headline split or incomplete data — check original summary',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no news and no search matches have distinct empty states', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewsBrowser(catalogue: fixture(noNews: true))),
      ),
    );
    expect(find.text('No news listed'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NewsBrowser(catalogue: fixture())),
      ),
    );
    await tester.enterText(find.byType(TextField), 'unknown topic');
    await tester.pumpAndSettle();
    expect(find.text('No matching news'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
