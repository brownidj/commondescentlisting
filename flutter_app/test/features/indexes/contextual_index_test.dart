import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/features/indexes/index_browser.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_engine.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

IndexEntity contextualEntity() => IndexEntity(
  id: 'api:fixture',
  kind: IndexKind.fossil,
  name: 'Lystrosaurus',
  subtype: 'genus',
  aliases: ['Lystrosaurus'],
  details: const IndexDetails(
    spoken: ['Lystrosaurus'],
    description: 'Drought-related mortality.',
    confidence: 'medium',
    bibliography: '{"year":2022}',
    originalPublication: '{"title":null}',
    sources: [
      IndexSource(url: 'https://example.org/paper', label: 'Publication'),
    ],
  ),
  anchors: const [
    IndexAnchor(
      guid: 'episode',
      quote: 'Lystrosaurus',
      passageId: 1,
      edition: 'one',
      passageText: 'Lystrosaurus died here.',
    ),
  ],
);

void main() {
  test(
    'compiled app asset keeps all categories and edition-bound evidence',
    () {
      final entries = IndexEntity.decode(
        File('assets/data/contextual_indexes.json').readAsStringSync(),
      );
      expect(entries.map((e) => e.kind).toSet(), IndexKind.values.toSet());
      for (final entry in entries) {
        expect(entry.details, isNotNull);
        expect(entry.review, IndexReview.suggested);
        expect(entry.anchors, isNotEmpty);
        expect(
          entry.anchors.every(
            (a) =>
                a.passageId != null &&
                a.edition != null &&
                a.passageText!.contains(a.quote),
          ),
          isTrue,
        );
        if (entry.isPublication) {
          expect(entry.name.startsWith('Untitled'), isFalse);
        }
      }
    },
  );
  test('retiring heuristic suggestions retains backups and confirmed/manual entries', () async {
    final document = indexDocument(['Some words.']);
    final store = MemoryIndexStore()
      ..document = IndexEntity.encode([
        IndexEntity(
          id: 'place:fake',
          kind: IndexKind.place,
          name: 'Fake',
          note: 'Possible place or geological unit in transcript wording.',
        ),
        IndexEntity(
          id: 'place:confirmed',
          kind: IndexKind.place,
          name: 'Confirmed',
          review: IndexReview.confirmed,
        ),
        IndexEntity(id: 'manual:one', kind: IndexKind.place, name: 'Manual'),
      ]);
    final controller = KnowledgeIndexController(
      catalogue: indexCatalogue(document),
      store: store,
      available: (_) => true,
      loadTranscript: (_) async => document,
      vocabulary: () async => IndexEntity.encode([]),
      contextualIndex: () async => IndexEntity.encode([]),
      enableHeuristicSuggestions: false,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.entities.map((e) => e.id), [
      'place:confirmed',
      'manual:one',
    ]);
    expect(IndexEntity.decode(controller.exportDocument), hasLength(3));
  });
  test(
    'contextual hits require the same passage, complete text and edition',
    () {
      final entry = contextualEntity();
      expect(
        indexOccurrences(entry, [
          indexDocument([
            'Lystrosaurus died here.',
            'Lystrosaurus in another context.',
          ]),
        ]).map((o) => o.cue.id),
        [1],
      );
      expect(
        indexOccurrences(entry, [
          indexDocument(['Lystrosaurus died here.'], edition: 'two'),
        ]),
        isEmpty,
      );
      expect(
        indexOccurrences(entry, [
          indexDocument(['Lystrosaurus did not die here.']),
        ]),
        isEmpty,
      );
      expect(
        indexOccurrences(entry, [
          indexDocument(['Unrelated.', 'Lystrosaurus died here.']),
        ]),
        isEmpty,
      );
    },
  );

  test('backup preserves detail, dates, sources and bound evidence', () {
    final result = IndexEntity.decode(IndexEntity.encode([contextualEntity()]))
        .single;
    expect(result.details!.bibliography, '{"year":2022}');
    expect(result.details!.sources.single.url, 'https://example.org/paper');
    expect(result.anchors.single.edition, 'one');
    final raw =
        jsonDecode(IndexEntity.encode([result])) as Map<String, dynamic>;
    raw['entries'][0]['anchors'][0]['passage_text'] = 'An invented quote';
    expect(() => IndexEntity.decode(jsonEncode(raw)), throwsFormatException);
    raw['entries'][0]['anchors'][0]['passage_text'] = 'Lystrosaurus died here.';
    raw['entries'][0]['details']['sources'][0]['url'] = 'javascript:alert(1)';
    expect(() => IndexEntity.decode(jsonEncode(raw)), throwsFormatException);
  });

  test(
    'refresh preserves an explicit rejection of bundled API evidence',
    () async {
      final document = indexDocument(['Lystrosaurus died here.']);
      final store = MemoryIndexStore();
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([contextualEntity()]),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.occurrences['api:fixture'], hasLength(1));
      final raw = jsonDecode(controller.exportDocument) as Map<String, dynamic>;
      raw['entries'][0]['review'] = 'rejected';
      await controller.replaceRegistry(jsonEncode(raw));
      await controller.refresh();
      expect(controller.entities.single.review, IndexReview.rejected);
      expect(controller.occurrences['api:fixture'], isEmpty);
      expect(controller.entities.single.details!.confidence, 'medium');
    },
  );

  testWidgets(
    'expandable native detail shows evidence, sources and passage controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = indexDocument(['Lystrosaurus died here.']);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([contextualEntity()]),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexBrowser(
              catalogue: controller.catalogue,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lystrosaurus'));
      await tester.pumpAndSettle();
      expect(find.text('Drought-related mortality.'), findsOneWidget);
      expect(find.textContaining('Model confidence: medium'), findsOneWidget);
      expect(find.text('Source: Publication'), findsOneWidget);
      expect(find.text('Passage 1 · 00:00:00'), findsOneWidget);
      expect(find.text('Open passage'), findsOneWidget);
      expect(find.text('Play'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
