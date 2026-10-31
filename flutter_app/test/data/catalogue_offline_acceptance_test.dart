import 'dart:io';

import 'package:common_descent_listing/data/bundled_catalogue.dart';
import 'package:common_descent_listing/data/catalogue_repository.dart';
import 'package:common_descent_listing/features/news/news_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('actual bundled catalogue loads and searches with Dart HTTP disabled', () async {
    await HttpOverrides.runZoned(
      () async {
        final timer = Stopwatch()..start();
        final catalogue = await CatalogueRepository(source: BundledCatalogue())
            .load();
        timer.stop();
        final loadMs = timer.elapsedMicroseconds / 1000;
        expect(catalogue.episodes, isNotEmpty);
        expect(
          catalogue.episodes.fold<int>(
            0,
            (sum, episode) => sum + episode.segments.length,
          ),
          catalogue.segments.length,
        );
        final controller = NewsController(catalogue);
        addTearDown(controller.dispose);
        timer.reset();
        timer.start();
        for (var index = 0; index < 100; index++) {
          controller.setQuery(index.isEven ? ' MOSASAURS ' : '255');
          expect(controller.visibleEntries, isNotEmpty);
        }
        timer.stop();
        debugPrint(
          'Acceptance measurement: ${catalogue.episodes.length} episodes, '
          '${catalogue.segments.length} segments, ${catalogue.newsCount} news records; '
          'asset load/parse/group ${loadMs.toStringAsFixed(1)} ms; '
          '100 searches ${(timer.elapsedMicroseconds / 1000).toStringAsFixed(1)} ms '
          '(test/debug environment; not a release benchmark).',
        );
      },
      createHttpClient: (_) => throw StateError(
        'Unexpected HTTP client during offline catalogue load',
      ),
    );
  });
}
