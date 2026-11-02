import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/playback_chapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'chapters deduplicate news, sort times, retain zero and omit missing times',
    () {
      Segment segment(
        int index,
        String type, {
        Duration? time,
        Duration? news,
        String? title,
        String? label,
      }) => Segment(
        sourceIndex: index,
        guid: 'episode',
        episodeTitle: 'Plants',
        type: type,
        startTime: time,
        newsStartTime: news,
        title: title,
        label: label,
      );
      final chapters = PlaybackChapter.forEpisode(
        Episode(
          guid: 'episode',
          title: 'Plants',
          number: '255',
          segments: [
            segment(
              0,
              'Main Discussion',
              time: const Duration(hours: 1),
              title: 'Plants',
              label: 'Main discussion, Part 2',
            ),
            segment(1, 'News', news: const Duration(minutes: 5), title: 'One'),
            segment(2, 'News', news: const Duration(minutes: 5), title: 'Two'),
            segment(
              3,
              'Main Discussion',
              time: Duration.zero,
              title: 'Plants',
              label: 'Main discussion, Part 1',
            ),
            segment(4, 'Main Discussion'),
          ],
        ),
      );
      expect(chapters.map((chapter) => chapter.title), [
        'Plants - Part 1',
        'News',
        'Plants - Part 2',
      ]);
      expect(chapters.map((chapter) => chapter.start.inSeconds), [
        0,
        300,
        3600,
      ]);
    },
  );
}
