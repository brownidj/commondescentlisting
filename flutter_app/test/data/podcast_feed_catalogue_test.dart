import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/catalogue_repository.dart';
import 'package:common_descent_listing/data/local_catalogue.dart';
import 'package:common_descent_listing/data/podcast_feed_catalogue.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Catalogue> catalogue(String source) =>
    CatalogueRepository(source: LocalCatalogueSource(source)).load();

String feed(String items) =>
    '<rss><channel><title>Common Descent</title>$items</channel></rss>';
String item(String guid, String title, String description) =>
    '''
<item><guid>$guid</guid><title>$title</title>
<pubDate>Sat, 24 Oct 2026 19:00:00 -0500</pubDate>
<link>https://example.org/episode</link>
<enclosure url="https://example.org/audio.mp3"/>
<description><![CDATA[$description]]></description></item>''';

void main() {
  late Catalogue previous;
  setUp(() async {
    previous = await catalogue(
      jsonEncode({
        'podcast': {'title': 'Common Descent'},
        'segments': [
          {
            'guid': 'old',
            'episode_title': 'Archive',
            'segment_type': 'Episode',
          },
        ],
      }),
    );
  });

  test('extracts metadata, converts timezone and retains archive', () async {
    final result = await catalogue(
      PodcastFeedCatalogue().mergeFeed(
        feed(
          item(
            'new',
            'Episode 256 - New &amp; Old',
            '<p>In the news: teeth; and bones.</p><p>News: 00:05:30</p>'
                '<p>Main discussion Part 1: 00:30:00</p>'
                '<p>Main discussion Part 2: 01:10:00</p>',
          ),
        ),
        previous,
      ),
    );
    expect(result.episodes.length, 2);
    final episode = result.episodes.first;
    expect(episode.number, '256');
    expect(episode.title, 'New & Old');
    expect(episode.publishedAt, DateTime.utc(2026, 10, 25));
    expect(episode.newsCount, 2);
    expect(
      episode.segments.first.newsStartTime,
      const Duration(minutes: 5, seconds: 30),
    );
    expect(episode.segments.first.needsReview, isTrue);
    expect(
      episode.segments.last.startTime,
      const Duration(hours: 1, minutes: 10),
    );
    expect(result.episodes.last.title, 'Archive');
  });

  test('matching GUID is refreshed without duplication', () async {
    final result = await catalogue(
      PodcastFeedCatalogue().mergeFeed(
        feed(item('old', 'Side episode', 'Some show notes')),
        previous,
      ),
    );
    expect(result.episodes.single.title, 'Side episode');
    expect(result.episodes.single.isSideEpisode, isTrue);
  });

  test('rejects empty, malformed and duplicate feeds', () {
    final validItem = item('one', 'Episode 1 - Title', '');
    for (final source in [
      '<rss>',
      feed(''),
      feed('$validItem$validItem'),
      feed('<item><title>No GUID</title></item>'),
    ]) {
      expect(
        () => PodcastFeedCatalogue().mergeFeed(source, previous),
        throwsA(isA<Exception>()),
      );
    }
  });

  test('saved RSS matches existing generator metadata', () async {
    final bundled = await catalogue(
      await File('assets/data/segments.yaml').readAsString(),
    );
    final result = await catalogue(
      PodcastFeedCatalogue().mergeFeed(
        await File('../data/segments.rss.xml').readAsString(),
        bundled,
      ),
    );
    expect(result.episodes.length, bundled.episodes.length);
    expect(result.newsCount, bundled.newsCount);
    expect(result.segments.length, bundled.segments.length);
    for (var i = 0; i < result.segments.length; i++) {
      final actual = result.segments[i];
      final expected = bundled.segments[i];
      expect(
        [
          actual.guid,
          actual.episodeTitle,
          actual.title,
          actual.type,
          actual.label,
          actual.startTime,
          actual.newsStartTime,
          actual.publishedAt,
        ],
        [
          expected.guid,
          expected.episodeTitle,
          expected.title,
          expected.type,
          expected.label,
          expected.startTime,
          expected.newsStartTime,
          expected.publishedAt,
        ],
      );
    }
  });
}
