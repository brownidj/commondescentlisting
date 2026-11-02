import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fromNews in [false, true]) {
    testWidgets(
      'scroll and summary expansion restore independently (fromNews=$fromNews)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final segments = List.generate(
          30,
          (index) => Segment(
            sourceIndex: index,
            guid: 'episode',
            episodeTitle: 'Plants',
            episodeNumber: '255',
            type: 'News',
            title: 'Headline $index',
            newsRaw: 'Original summary',
            needsReview: true,
          ),
        );
        final episode = Episode(
          guid: 'episode',
          title: 'Plants',
          number: '255',
          segments: segments,
        );
        final bucket = PageStorageBucket();
        final show = ValueNotifier(true);
        addTearDown(show.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PageStorage(
                bucket: bucket,
                child: ValueListenableBuilder<bool>(
                  valueListenable: show,
                  builder: (context, visible, _) => visible
                      ? EpisodeDetail(
                          episode: episode,
                          selectedSegmentId: fromNews
                              ? segments.first.sessionId
                              : null,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        ScrollPosition position() => tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;

        // Save a double scroll offset, dispose the tiles, then restore them.
        position().jumpTo(1200);
        await tester.pumpAndSettle();
        show.value = false;
        await tester.pumpAndSettle();
        show.value = true;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(position().pixels, closeTo(1200, 1));
        position().jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(find.text('Original news summary'), findsNothing);
        if (!fromNews) return;
        final summary = find.text('Selected item original summary');
        await tester.ensureVisible(summary);
        await tester.tap(summary);
        await tester.pumpAndSettle();
        expect(find.text('Original summary'), findsOneWidget);

        // Saving a bool expansion flag must not overwrite the double offset.
        show.value = false;
        await tester.pumpAndSettle();
        show.value = true;
        await tester.pumpAndSettle();
        position().jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Original summary'), findsOneWidget);
      },
    );
  }
}
