import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('episode side classification handles blank and numbered values', () {
    for (final number in [null, '', '  ', '\t\n']) {
      final episode = Episode(
        guid: 'episode',
        title: 'Episode',
        number: number,
        segments: const [],
      );
      expect(episode.isSideEpisode, isTrue, reason: 'number: $number');
    }

    for (final number in ['37.5', ' 37.5 ', '18A']) {
      final episode = Episode(
        guid: 'episode',
        title: 'Episode',
        number: number,
        segments: const [],
      );
      expect(episode.isSideEpisode, isFalse, reason: 'number: $number');
      expect(episode.number, number);
    }
  });

  test('segment side classification uses the segment number', () {
    const blankNumber = Segment(
      sourceIndex: 0,
      guid: 'episode',
      episodeTitle: 'Episode',
      episodeNumber: '  ',
      type: 'News',
    );
    const numbered = Segment(
      sourceIndex: 1,
      guid: 'episode',
      episodeTitle: 'Episode',
      episodeNumber: '18A',
      type: 'News',
    );

    expect(blankNumber.isSideEpisode, isTrue);
    expect(numbered.isSideEpisode, isFalse);
  });

  test('review notice flags and episode aggregation share one rule', () {
    const noNotice = Segment(
      sourceIndex: 0,
      guid: 'episode',
      episodeTitle: 'Episode',
      type: 'News',
      needsReview: false,
      headlineSplitMethod: '  ',
    );
    const needsReview = Segment(
      sourceIndex: 1,
      guid: 'episode',
      episodeTitle: 'Episode',
      type: 'News',
      needsReview: true,
    );
    const splitAutomatically = Segment(
      sourceIndex: 2,
      guid: 'episode',
      episodeTitle: 'Episode',
      type: 'News',
      headlineSplitMethod: 'automatic',
    );
    final unflaggedEpisode = Episode(
      guid: 'unflagged',
      title: 'Unflagged',
      number: '1',
      segments: const [noNotice],
    );
    final flaggedEpisode = Episode(
      guid: 'flagged',
      title: 'Flagged',
      number: '2',
      segments: const [noNotice, needsReview],
    );

    expect(noNotice.hasReviewNotice, isFalse);
    expect(needsReview.hasReviewNotice, isTrue);
    expect(splitAutomatically.hasReviewNotice, isTrue);
    expect(unflaggedEpisode.hasReviewNotice, isFalse);
    expect(flaggedEpisode.hasReviewNotice, isTrue);
  });
}