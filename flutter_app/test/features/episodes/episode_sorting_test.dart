import 'dart:convert';

import 'package:common_descent_listing/data/catalogue_parser.dart';
import 'package:common_descent_listing/data/bundled_transcripts.dart';
import 'package:common_descent_listing/data/catalogue_repository.dart';
import 'package:common_descent_listing/features/episodes/episode_browser.dart';
import 'package:common_descent_listing/features/episodes/episode_controller.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Episode episode(String guid, String title, String? date, {bool side = false}) =>
    Episode(
      guid: guid,
      title: title,
      number: side ? null : '37.5',
      publishedAt: date == null ? null : DateTime.parse(date),
      segments: const [],
    );

class MemorySource implements CatalogueSource {
  MemorySource(this.rows);
  final List<Map<String, Object?>> rows;
  @override
  String get name => 'sorting fixture';
  @override
  Future<String> load() async => jsonEncode({
    'podcast': {'title': 'Podcast'},
    'segments': rows,
  });
}

void main() {
  test(
    'Transcribed uses bundled availability when no callback is supplied',
    () {
      final controller = EpisodeController([
        episode(BundledTranscripts.episode208Guid, 'Karoo', null),
        episode('not-transcribed', 'Missing', null),
      ], hasTranscript: null);
      addTearDown(controller.dispose);
      controller.setFilter(EpisodeFilter.transcribed);
      expect(
        controller.visibleEpisodes.single.guid,
        BundledTranscripts.episode208Guid,
      );
      expect(controller.order, EpisodeOrder.latestFirst);
    },
  );

  test(
    'Transcribed combines availability, search and sorting for main and side',
    () {
      final available = {'main', 'side'};
      final controller = EpisodeController([
        episode('main', 'Zebra', '2026-01-01T00:00:00Z'),
        episode('side', 'Alpha', '2025-01-01T00:00:00Z', side: true),
        episode('missing', 'No transcript', '2026-02-01T00:00:00Z'),
      ], hasTranscript: available.contains);
      addTearDown(controller.dispose);
      controller.setFilter(EpisodeFilter.transcribed);
      expect(controller.visibleEpisodes.map((e) => e.guid), ['main', 'side']);
      expect(controller.titleFilteredGuids, {'main', 'side'});
      controller.setOrder(EpisodeOrder.titleAscending);
      expect(controller.visibleEpisodes.map((e) => e.guid), ['side', 'main']);
      controller.setQuery('Alpha');
      expect(controller.visibleEpisodes.single.guid, 'side');
      controller.setQuery('');
      controller.setIndexEntries([
        EpisodeIndexEntry(
          name: 'Mammal',
          terms: ['Mammal'],
          episodeGuids: ['main', 'missing'],
        ),
      ]);
      controller.setIndexQuery('Mammal');
      expect(controller.visibleEpisodes.single.guid, 'main');
      controller.setIndexQuery('');
      controller.select(controller.visibleEpisodes.first);
      available.clear();
      controller.refreshTranscriptAvailability();
      expect(controller.visibleEpisodes, isEmpty);
      expect(controller.selected, isNull);
      available.add('missing');
      controller.refreshTranscriptAvailability();
      expect(controller.visibleEpisodes.single.guid, 'missing');
    },
  );

  final episodes = [
    episode('old', 'zebra', '2025-01-01T00:00:00Z'),
    episode('unknown', 'Alpha', null),
    episode('new', 'beta', '2026-01-01T18:00:00Z'),
    episode('side', 'Side', '2026-01-01T12:00:00Z', side: true),
    episode('tie', 'BETA', '2026-01-01T18:00:00Z'),
    episode('old-side', 'Other', '2024-01-01T00:00:00Z', side: true),
  ];

  test('dates use publication instants, stable ties and undated last', () {
    final controller = EpisodeController(episodes);
    addTearDown(controller.dispose);
    List<String> ids() =>
        controller.visibleEpisodes.map((e) => e.guid).toList();
    expect(ids(), ['new', 'tie', 'side', 'old', 'old-side', 'unknown']);
    controller.select(episodes[2]);
    controller.setOrder(EpisodeOrder.earliestFirst);
    expect(ids(), ['old-side', 'old', 'side', 'new', 'tie', 'unknown']);
    expect(controller.selected, same(episodes[2]));
    expect(controller.episodes, orderedEquals(episodes));
    controller.setQuery('beta');
    expect(ids(), ['new', 'tie']);
    controller.setFilter(EpisodeFilter.numbered);
    expect(ids(), ['new', 'tie']);
  });

  test('title directions ignore case; each filter remembers its order', () {
    final controller = EpisodeController(episodes);
    addTearDown(controller.dispose);
    List<String> ids() =>
        controller.visibleEpisodes.map((e) => e.guid).toList();
    controller.setOrder(EpisodeOrder.earliestFirst);
    controller.setFilter(EpisodeFilter.numbered);
    expect(ids(), ['unknown', 'new', 'tie', 'old']);
    controller.setOrder(EpisodeOrder.titleDescending);
    expect(ids(), ['old', 'new', 'tie', 'unknown']);
    controller.setFilter(EpisodeFilter.side);
    expect(ids(), ['side', 'old-side']);
    controller.setOrder(EpisodeOrder.titleAscending);
    expect(controller.order, EpisodeOrder.titleAscending);
    expect(ids(), ['old-side', 'side']);
    controller.setOrder(EpisodeOrder.earliestFirst);
    expect(ids(), ['old-side', 'side']);
    controller.setFilter(EpisodeFilter.all);
    expect(controller.order, EpisodeOrder.earliestFirst);
    controller.setFilter(EpisodeFilter.numbered);
    expect(controller.order, EpisodeOrder.titleDescending);
  });

  test('alphabetical filing skips leading function words with stable ties', () {
    final controller = EpisodeController([
      episode('z', 'The Zebra', null),
      episode('o', 'On the Origin of Species', null),
      episode('a', 'An Apple', null),
      episode('same', 'Origin of Species', null, side: true),
      episode('all-words', 'The', null),
    ]);
    addTearDown(controller.dispose);
    controller.setOrder(EpisodeOrder.titleAscending);
    expect(controller.visibleEpisodes.map((e) => e.guid), [
      'a',
      'o',
      'same',
      'all-words',
      'z',
    ]);
    controller.setOrder(EpisodeOrder.titleDescending);
    expect(controller.visibleEpisodes.map((e) => e.guid), [
      'z',
      'all-words',
      'o',
      'same',
      'a',
    ]);
    expect(controller.episodes.first.title, 'The Zebra');
    controller.setFilter(EpisodeFilter.side);
    expect(controller.availableOrders, contains(EpisodeOrder.titleAscending));
  });

  Map<String, Object?> row([String? date]) => {
    'guid': 'one',
    'episode_title': 'One',
    'episode_number': '1',
    'segment_type': 'News',
    'episode_published_at': ?date,
  };

  test(
    'publication metadata is optional, strict and grouped by GUID',
    () async {
      final source = MemorySource([row(), row('2026-01-01T18:00:00Z')]);
      final catalogue = await CatalogueRepository(source: source).load();
      expect(
        catalogue.episodes.single.publishedAt,
        DateTime.utc(2026, 1, 1, 18),
      );
      expect(catalogue.segments.first.publishedAt, isNull);
      for (final invalid in ['2026-02-30T00:00:00Z', '2026-01-01', 'bad']) {
        expect(
          () => CatalogueParser().parse(
            jsonEncode({
              'podcast': {'title': 'Podcast'},
              'segments': [row(invalid)],
            }),
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        CatalogueRepository(
          source: MemorySource([
            row('2026-01-01T18:00:00Z'),
            row('2025-01-01T18:00:00Z'),
          ]),
        ).load(),
        throwsFormatException,
      );
    },
  );

  testWidgets('browser offers date and alphabetical orders for every filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeBrowser(
            catalogue: Catalogue(
              podcast: const Podcast(title: 'Podcast'),
              segments: const [],
              episodes: episodes,
              sourceName: 'fixture',
            ),
          ),
        ),
      ),
    );
    Future<void> choose(String label) async {
      await tester.tap(find.byType(DropdownButtonFormField<EpisodeOrder>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await choose('Earliest to latest');
    expect(find.text('Earliest to latest'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Main'));
    await tester.pumpAndSettle();
    await choose('Z–A');
    expect(find.text('Z–A'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Side'));
    await tester.pumpAndSettle();
    expect(find.text('Latest to earliest'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.text('Earliest to latest'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
