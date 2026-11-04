import 'package:common_descent_listing/features/episodes/episode_browser.dart';
import 'package:common_descent_listing/features/episodes/episode_controller.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../indexes/index_test_support.dart';

void main() {
  test('title and index search are distinct and preserve filters, sorting and empty queries', () {
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
        episodeGuids: ['a'],
      ),
      EpisodeIndexEntry(
        name: 'Reptiles',
        terms: ['Reptiles', 'marine reptile'],
        episodeGuids: ['a', 'b'],
      ),
    ]);
    controller.setQuery('MARINE REPTILE');
    expect(controller.visibleEpisodes, isEmpty);
    controller.setSearchTarget(EpisodeSearchTarget.indexed);
    expect(controller.visibleEpisodes, [a, b]);
    expect(controller.matchingIndexNames('a'), ['Elasmosaurus', 'Reptiles']);
    controller.setFilter(EpisodeFilter.numbered);
    expect(controller.visibleEpisodes, [a]);
    controller.setOrder(EpisodeOrder.titleDescending);
    expect(controller.visibleEpisodes, [a]);
    controller.setFilter(EpisodeFilter.side);
    expect(controller.visibleEpisodes, [b]);
    controller.setFilter(EpisodeFilter.all);
    controller.setQuery('');
    expect(controller.visibleEpisodes, [a, b]);
    controller.setSearchTarget(EpisodeSearchTarget.titles);
    controller.setQuery('72');
    expect(controller.visibleEpisodes, [a]);
    controller.setQuery('Forest');
    expect(controller.visibleEpisodes, [b]);
  });

  testWidgets(
    'index mode loads lazily, matches aliases and excludes rejected, deleted and stale evidence',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = indexDocument(['Elasmosaurus lived here.']);
      final catalogue = indexCatalogue(document);
      var loads = 0;
      IndexAnchor anchor({String edition = 'one'}) => IndexAnchor(
        guid: 'episode',
        quote: 'Elasmosaurus',
        passageId: 1,
        edition: edition,
        passageText: document.transcript.cues.single.text,
      );
      IndexEntity entity(
        String id,
        String name, {
        IndexReview review = IndexReview.suggested,
        bool deleted = false,
        String edition = 'one',
      }) => IndexEntity(
        id: id,
        kind: IndexKind.fossil,
        name: name,
        aliases: id == 'taxon' ? ['marine reptile'] : [],
        review: review,
        deleted: deleted,
        anchors: [anchor(edition: edition)],
        details: const IndexDetails(),
      );
      final store = MemoryIndexStore()..refuse = true;
      final knowledge = KnowledgeIndexController(
        catalogue: catalogue,
        store: store,
        available: (_) => true,
        loadTranscript: (_) async {
          loads++;
          return document;
        },
        enableHeuristicSuggestions: false,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([
          entity('taxon', 'Elasmosaurus'),
          entity('rejected', 'Discarded taxon', review: IndexReview.rejected),
          entity('deleted', 'Deleted taxon', deleted: true),
          entity('stale', 'Stale taxon', edition: 'old'),
        ]),
      );
      addTearDown(knowledge.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodeBrowser(
              catalogue: catalogue,
              indexController: knowledge,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 0);
      await tester.enterText(find.byType(TextField), 'marine reptile');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('episode-episode')), findsNothing);
      await tester.tap(
        find.byType(DropdownButtonFormField<EpisodeSearchTarget>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Index').last);
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.text('Index search unavailable'), findsOneWidget);
      expect(find.text('No matching episodes'), findsNothing);
      store.refuse = false;
      await tester.tap(find.text('Retry index search'));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.byKey(const ValueKey('episode-episode')), findsOneWidget);
      expect(find.text('Index: Elasmosaurus'), findsOneWidget);
      for (final term in ['Discarded taxon', 'Deleted taxon', 'Stale taxon']) {
        await tester.enterText(find.byType(TextField), term);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('episode-episode')), findsNothing);
      }
      await tester.enterText(find.byType(TextField), 'marine reptile');
      await tester.pumpAndSettle();
      await knowledge.deleteEntity(
        'taxon',
        expectedRevision: knowledge.registryRevision!,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('episode-episode')), findsNothing);
      await tester.tap(
        find.byType(DropdownButtonFormField<EpisodeSearchTarget>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Episode titles').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sample');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('episode-episode')), findsOneWidget);
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
