import 'package:common_descent_listing/features/episodes/transcript_passage_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    ValueNotifier<int?> follow, {
    double height = 500,
    double Function(int)? rowHeight,
    VoidCallback? sync,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: height,
              child: ValueListenableBuilder<int?>(
                valueListenable: follow,
                builder: (_, active, _) => TranscriptPassageList(
                  itemCount: 100,
                  followIndex: active,
                  resetToken: 0,
                  itemBuilder: (_, index) => SizedBox(
                    key: ValueKey('row-$index'),
                    height: index == 0 ? 120 : rowHeight?.call(index) ?? 80,
                    child: Row(
                      children: [
                        Expanded(child: Text('Passage $index')),
                        IconButton(
                          key: ValueKey('sync-$index'),
                          onPressed: sync,
                          icon: const Icon(Icons.sync),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'highlight moves without moving buttons, then retains bottom three rows',
    (tester) async {
      final follow = ValueNotifier<int?>(1);
      addTearDown(follow.dispose);
      var synced = 0;
      await mount(tester, follow, sync: () => synced++);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      final button = find.byKey(const ValueKey('sync-4'));
      final original = tester.getRect(button);
      // Six rows fit fully. The first four highlights leave the viewport fixed.
      for (final index in [2, 3, 4]) {
        follow.value = index;
        await tester.pumpAndSettle();
        expect(tester.getRect(button), original);
      }
      await tester.tap(button);
      expect(synced, 1);
      follow.value = 5; // Second-last of the old six fully visible passages.
      await tester.pumpAndSettle();
      for (var index = 4; index <= 6; index++) {
        expect(
          tester.getTopLeft(find.byKey(ValueKey('row-$index'))).dy,
          closeTo(viewport.top + (index - 4) * 80, 0.5),
        );
      }
      final afterPage = tester.getRect(find.byKey(const ValueKey('sync-6')));
      for (final index in [6, 7]) {
        follow.value = index;
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(const ValueKey('sync-6'))), afterPage);
      }
      follow.value = 8; // New viewport contains passages 4 through 9.
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-7'))).dy,
        closeTo(viewport.top, 0.5),
      );
      expect(find.byType(IconButton).evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overlap uses laid-out variable heights rather than estimated rows',
    (tester) async {
      final follow = ValueNotifier<int?>(1);
      addTearDown(follow.dispose);
      const heights = [100.0, 60.0, 120.0, 80.0, 140.0, 60.0, 100.0];
      await mount(
        tester,
        follow,
        rowHeight: (index) => heights[(index - 1) % heights.length],
      );
      final top = tester.getRect(find.byType(CustomScrollView)).top;
      // Passages 1..5 exactly fill 500 px; paging at 4 must retain 3,4,5.
      follow.value = 4;
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-3'))).dy,
        closeTo(top, 0.5),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-4'))).dy,
        closeTo(top + 120, 0.5),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-5'))).dy,
        closeTo(top + 200, 0.5),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tiny viewports, pauses and distant seeks make progress without repaging loops',
    (tester) async {
      final follow = ValueNotifier<int?>(1);
      addTearDown(follow.dispose);
      await mount(tester, follow, height: 140);
      final top = tester.getRect(find.byType(CustomScrollView)).top;
      follow.value = 2;
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-2'))).dy,
        closeTo(top, 0.5),
      );
      follow.value = null;
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(scroll.position.pixels + 160);
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, 160);
      follow.value = 80;
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-80'))).dy,
        closeTo(top, 0.5),
      );
      follow.value = 99;
      await tester.pumpAndSettle();
      final pageKey = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .key;
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.widget<CustomScrollView>(find.byType(CustomScrollView)).key,
        pageKey,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
