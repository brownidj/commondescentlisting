import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/catalogue_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

class MemorySource implements CatalogueSource {
  MemorySource(this.contents);
  final String contents;
  @override
  String get name => 'test.yaml';
  @override
  Future<String> load() async => contents;
}

String fixture(List<Map<String, Object?>> rows) => jsonEncode({
  'podcast': {'title': 'Common Descent'},
  'segments': rows,
});
Map<String, Object?> row(String guid, String? number, String type) => {
  'guid': guid,
  'episode_number': number,
  'episode_title': 'Shared title',
  'segment_type': type,
  'segment_title': 'Repeated headline',
};

void main() {
  test('conflicting audio for the same episode is rejected', () async {
    final repository = CatalogueRepository(
      source: MemorySource(
        fixture([
          {
            ...row('same', '255', 'News'),
            'audio_url': 'https://example.com/one.mp3',
          },
          {
            ...row('same', '255', 'Main Discussion'),
            'audio_url': 'https://example.com/two.mp3',
          },
        ]),
      ),
    );
    await expectLater(repository.load(), throwsFormatException);
  });
  test(
    'GUID grouping preserves episode order, segment order and duplicate news',
    () async {
      final repository = CatalogueRepository(
        source: MemorySource(
          fixture([
            row('side', null, 'Episode'),
            row('main', '18A', 'News'),
            row('other', '37.5', 'Future Type'),
            row('main', '18A', 'News'),
            row('main', '18A', 'Main Discussion'),
          ]),
        ),
      );
      final data = await repository.load();
      expect(data.episodes.map((e) => e.guid), ['side', 'main', 'other']);
      expect(data.segments, hasLength(5));
      expect(data.episodes[1].segments.map((s) => s.sourceIndex), [1, 3, 4]);
      expect(data.episodes[1].newsCount, 2);
      expect(data.segments.map((s) => s.sessionId).toSet(), hasLength(5));
      expect(() => data.episodes.clear(), throwsUnsupportedError);
      expect(() => data.episodes[1].segments.clear(), throwsUnsupportedError);
    },
  );

  test(
    'rejects contradictory episode metadata with a source diagnostic',
    () async {
      final repository = CatalogueRepository(
        source: MemorySource(
          fixture([
            row('same', '18A', 'News'),
            row('same', '18B', 'Main Discussion'),
          ]),
        ),
      );
      await expectLater(
        repository.load(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'diagnostic',
            allOf(
              contains('test.yaml'),
              contains('record 2'),
              contains('conflicting'),
            ),
          ),
        ),
      );
    },
  );

  test(
    'bundled snapshot retains every source record and distinct GUID',
    () async {
      final source = await File('assets/data/segments.yaml').readAsString();
      final raw = (loadYaml(source) as Map)['segments'] as List;
      final expectedGuids = raw.map((row) => (row as Map)['guid']).toSet();
      final data = await CatalogueRepository(source: MemorySource(source))
          .load();
      expect(data.segments, hasLength(raw.length));
      expect(data.episodes.map((e) => e.guid).toSet(), expectedGuids);
      expect(
        data.episodes.fold<int>(
          0,
          (sum, episode) => sum + episode.segments.length,
        ),
        raw.length,
      );
      for (var index = 0; index < raw.length; index++) {
        expect(data.segments[index].guid, (raw[index] as Map)['guid']);
        expect(
          data.segments[index].title,
          (raw[index] as Map)['segment_title'],
        );
      }
      final plant = data.episodes.singleWhere((e) => e.number == '255');
      expect(plant.audioUri?.scheme, 'https');
      expect(
        data.episodes.every((episode) => episode.audioUri != null),
        isTrue,
      );
      expect(plant.segments.where((s) => s.isNews).map((s) => s.title), [
        'mosasaurs',
        'more mosasaurs',
        'Jurassic mammals',
        'horned dinosaurs',
      ]);
      expect(
        plant.segments
            .where((s) => s.isNews)
            .every(
              (s) =>
                  s.startTime == null &&
                  s.newsStartTime == const Duration(minutes: 5, seconds: 25),
            ),
        isTrue,
      );
      final discussion = plant.segments.where(
        (s) => s.type == 'Main Discussion',
      );
      expect(discussion.map((s) => s.startTime), [
        const Duration(minutes: 47, seconds: 35),
        const Duration(hours: 1, minutes: 16, seconds: 5),
      ]);
    },
  );
}
