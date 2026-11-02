import 'dart:convert';

import 'package:common_descent_listing/data/catalogue_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> record([Map<String, Object?> fields = const {}]) => {
  'guid': 'episode-1',
  'episode_title': 'Plants',
  'episode_number': '37.5',
  'segment_type': 'News',
  ...fields,
};
String document(
  List<Object?> records, [
  Map<String, Object?> extra = const {},
]) => jsonEncode({
  'podcast': {'title': 'Common Descent'},
  'segments': records,
  ...extra,
});

void main() {
  final parser = CatalogueParser();

  test('audio URLs are optional strings and malformed types are rejected', () {
    final segments = parser
        .parse(
          document([
            record(),
            record({'audio_url': 'https://example.com/episode.mp3'}),
          ]),
        )
        .segments;
    expect(segments.first.audioUrl, isNull);
    expect(segments.last.audioUrl, 'https://example.com/episode.mp3');
    expect(
      () => parser.parse(
        document([
          record({'audio_url': 123}),
        ]),
      ),
      throwsFormatException,
    );
  });

  test(
    'nullable fields, fractional/suffixed numbers, and future fields survive',
    () {
      final data = parser.parse(
        document([
          record({'future': 'ignored'}),
          record({'episode_number': '18A', 'segment_type': 'Future Type'}),
          record({'episode_number': null}),
          record({'episode_number': 37.5}),
        ]),
      );
      expect(data.segments.map((s) => s.episodeNumber), [
        '37.5',
        '18A',
        null,
        '37.5',
      ]);
      expect(data.segments[1].type, 'Future Type');
      expect(data.segments.first.startTime, isNull);
      expect(data.segments.first.needsReview, isNull);
      expect(data.segments.first.title, isNull);
      expect(() => data.segments.clear(), throwsUnsupportedError);
    },
  );

  test(
    'timestamps retain news and discussion meanings; zero is not missing',
    () {
      final segments = parser
          .parse(
            document([
              record({'news_start_time': '00:05:25', 'start_time': null}),
              record({'start_time': '01:16:05'}),
              record({'start_time': '76:05'}),
              record({'start_time': '00:00'}),
            ]),
          )
          .segments;
      expect(segments.first.startTime, isNull);
      expect(
        segments.first.newsStartTime,
        const Duration(minutes: 5, seconds: 25),
      );
      expect(
        segments[1].startTime,
        const Duration(hours: 1, minutes: 16, seconds: 5),
      );
      expect(segments[2].startTime, segments[1].startTime);
      expect(segments.last.startTime, Duration.zero);
    },
  );

  test('rejects invalid timestamps instead of normalising them', () {
    for (final time in [
      '00:60:00',
      '00:00:60',
      '-1:00',
      '1:2',
      '',
      '999999999999999999999999999999:00',
    ]) {
      expect(
        () => parser.parse(
          document([
            record({'start_time': time}),
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'invalid required/optional fields identify source, record, and field',
    () {
      for (final fields in <Map<String, Object?>>[
        {'guid': ' '},
        {'episode_title': null},
        {'segment_type': 12},
        {'needs_review': 'true'},
        {'segment_title': 9},
        {'news_raw': []},
        {'episode_number': true},
        {'source_url': false},
      ]) {
        final field = fields.keys.single;
        expect(
          () => parser.parse(
            document([record(), record(fields)]),
            sourceName: 'import.yaml',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'diagnostic',
              allOf(
                contains('import.yaml'),
                contains('record 2'),
                contains(field),
              ),
            ),
          ),
        );
      }
    },
  );

  test('rejects malformed documents and unsupported schema, accepts empty catalogue', () {
    for (final input in [
      '',
      '[',
      '[]',
      '{}',
      'podcast: []\nsegments: []',
      document([], {'segments': {}}),
      document([], {'schema_version': 2}),
    ]) {
      expect(() => parser.parse(input), throwsA(isA<FormatException>()));
    }
    expect(parser.parse(document([])).segments, isEmpty);
  });

  test('only safe HTTP(S) episode links become actionable', () {
    for (final url in [
      'javascript:alert(1)',
      'file:///tmp/a',
      '/relative',
      'https://',
      'https://user:password@example.com',
    ]) {
      expect(
        parser
            .parse(
              document([
                record({'source_url': url}),
              ]),
            )
            .segments
            .single
            .sourceUri,
        isNull,
      );
    }
    expect(
      parser
          .parse(
            document([
              record({'source_url': 'https://example.com/episode'}),
            ]),
          )
          .segments
          .single
          .sourceUri
          ?.host,
      'example.com',
    );
  });
}
