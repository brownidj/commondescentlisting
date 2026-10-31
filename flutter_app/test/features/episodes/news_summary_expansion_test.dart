import 'package:common_descent_listing/features/episodes/episode_detail.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selected summary tolerates repeated toggles, scroll and copy', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const raw =
        'ancient whales, aquatic sloths, marine reptiles, and meat-eating dung beetles.';
    const title = 'Back to the Water (Secondarily Aquatic Vertebrates)';
    final segments = List.generate(
      20,
      (index) => Segment(
        sourceIndex: index,
        guid: 'episode-231',
        episodeTitle: title,
        episodeNumber: '231',
        type: 'News',
        title: 'Headline $index',
        newsRaw: raw,
        needsReview: true,
      ),
    );
    final episode = Episode(
      guid: 'episode-231',
      title: title,
      number: '231',
      segments: segments,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EpisodeDetail(
            episode: episode,
            selectedSegmentId: segments[3].sessionId,
          ),
        ),
      ),
    );
    final tile = find.text('Selected item original summary');
    for (var index = 0; index < 4; index++) {
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Copy summary'));
    await tester.pumpAndSettle();
    expect(copied, raw);
    expect(find.text('Summary copied'), findsOneWidget);
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(1800);
    await tester.pumpAndSettle();
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(raw), findsOneWidget);
  });
}
