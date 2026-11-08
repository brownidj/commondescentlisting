import 'package:common_descent_listing/features/episodes/episode_browser.dart';
import 'package:common_descent_listing/features/episodes/episode_controller.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../indexes/index_test_support.dart';

final titleSearch = find.byKey(const ValueKey('episode-title-search'));
final transcriptSearch = find.byKey(
  const ValueKey('episode-transcript-search'),
);

Future<KnowledgeIndexController> mountSearch(
  WidgetTester tester, {
  List<String> texts = const ['The Karoo contains rocks of many ages.'],
  List<IndexEntity> entries = const [],
  VoidCallback? onLoad,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final document = indexDocument(texts);
  final knowledge = KnowledgeIndexController(
    catalogue: indexCatalogue(document),
    store: MemoryIndexStore(),
    available: (_) => true,
    loadTranscript: (_) async {
      onLoad?.call();
      return document;
    },
    enableHeuristicSuggestions: false,
    vocabulary: () async => IndexEntity.encode([]),
    contextualIndex: () async => IndexEntity.encode(entries),
  );
  addTearDown(knowledge.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EpisodeBrowser(
          catalogue: indexCatalogue(document),
          indexController: knowledge,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return knowledge;
}

Future<void> searchAndWait(WidgetTester tester, String query) async {
  await tester.enterText(transcriptSearch, query);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
}

void main() {
  test('title and index filters combine; direct results retain sorting and filters', () {
    final a = Episode(
      guid: 'a',
      title: 'Oceans',
      number: '72',
      segments: const [],
    );
    final b = Episode(
      guid: 'b',
      title: 'Forest',
      number: null,
      segments: const [],
    );
    final controller = EpisodeController([a, b]);
    addTearDown(controller.dispose);
    controller.setIndexEntries([
      EpisodeIndexEntry(
        name: 'Elasmosaurus',
        terms: ['Elasmosaurus', 'marine reptile'],
        episodeGuids: ['a', 'b'],
      ),
    ]);
    controller.setIndexQuery('MARINE REPTILE');
    expect(controller.visibleEpisodes, [a, b]);
    controller.setQuery('72');
    expect(controller.visibleEpisodes, [a]);
    controller.setQuery('');
    controller.setFilter(EpisodeFilter.side);
    expect(controller.visibleEpisodes, [b]);
    controller.setIndexQuery('rocks');
    expect(controller.visibleEpisodes, isEmpty);
    controller.showTranscriptMatches(['a', 'b']);
    expect(controller.visibleEpisodes, [b]);
    controller.setFilter(EpisodeFilter.all);
    controller.setOrder(EpisodeOrder.titleAscending);
    expect(controller.visibleEpisodes, [b, a]);
    controller.setIndexQuery('unmatched');
    expect(controller.showingTranscriptMatches, isFalse);
    expect(controller.visibleEpisodes, isEmpty);
    controller.setIndexQuery('');
    expect(controller.visibleEpisodes, [b, a]);
  });

  testWidgets(
    'two ordered fields use indexes first and do not offer fallback for a hit',
    (tester) async {
      var loads = 0;
      await mountSearch(
        tester,
        texts: ['Elasmosaurus lived here.'],
        onLoad: () => loads++,
        entries: [
          IndexEntity(
            id: 'taxon',
            kind: IndexKind.fossil,
            name: 'Elasmosaurus',
            aliases: ['marine reptile'],
            details: const IndexDetails(),
            anchors: const [
              IndexAnchor(
                guid: 'episode',
                quote: 'Elasmosaurus',
                passageId: 1,
                edition: 'one',
                passageText: 'Elasmosaurus lived here.',
              ),
            ],
          ),
        ],
      );
      expect(loads, 0);
      expect(
        tester.getTopLeft(titleSearch).dy,
        lessThan(tester.getTopLeft(transcriptSearch).dy),
      );
      expect(find.byType(DropdownButtonFormField<IndexKind>), findsNothing);
      await searchAndWait(tester, 'marine reptile');
      expect(loads, 1);
      expect(find.text('Index: Elasmosaurus'), findsOneWidget);
      expect(find.text('Search transcript text?'), findsNothing);
      expect(find.byKey(const ValueKey('episode-episode')), findsOneWidget);
      await tester.enterText(titleSearch, 'Different title');
      await tester.pump();
      expect(find.byKey(const ValueKey('episode-episode')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('declining fallback neither searches text nor adds results', (
    tester,
  ) async {
    final knowledge = await mountSearch(tester);
    await searchAndWait(tester, 'Karoo');
    expect(find.text('Search transcript text?'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-episode')), findsNothing);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(find.text('Transcript text match'), findsNothing);
    expect(knowledge.entities, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Search transcript text?'), findsNothing);
  });

  testWidgets(
    'fallback finds literal passages and can save reviewed category and edition evidence',
    (tester) async {
      final knowledge = await mountSearch(
        tester,
        texts: ['The Karoo contains rocks.', 'More Karoo rocks.'],
      );
      await searchAndWait(tester, 'Karoo');
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(find.text('Add results to the index?'), findsOneWidget);
      expect(knowledge.entities, isEmpty);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<IndexKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Places').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final entry = knowledge.entities.single;
      expect(entry.name, 'Karoo');
      expect(entry.kind, IndexKind.place);
      expect(entry.anchors.map((anchor) => anchor.passageId), [1, 2]);
      expect(entry.anchors.every((anchor) => anchor.edition == 'one'), isTrue);
      expect(knowledge.occurrences[entry.id], hasLength(2));
      expect(find.byKey(const ValueKey('episode-episode')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'declining addition keeps direct matches without saving an entry',
    (tester) async {
      final knowledge = await mountSearch(tester);
      await searchAndWait(tester, 'Karoo');
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.text('Transcript text match'), findsOneWidget);
      expect(knowledge.entities, isEmpty);
    },
  );

  for (final blocked in ['of', 'Karoo']) {
    testWidgets('fallback explains why $blocked cannot be added', (
      tester,
    ) async {
      final knowledge = await mountSearch(
        tester,
        entries: [
          if (blocked == 'Karoo')
            IndexEntity(
              id: 'deleted',
              kind: IndexKind.place,
              name: 'The Karoo',
              deleted: true,
            ),
        ],
      );
      await searchAndWait(tester, blocked);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(find.text('Entry cannot be added'), findsOneWidget);
      expect(
        find.textContaining(blocked == 'of' ? 'Prepositions' : 'deletion list'),
        findsOneWidget,
      );
      expect(knowledge.entities, isEmpty);
    });
  }
}
