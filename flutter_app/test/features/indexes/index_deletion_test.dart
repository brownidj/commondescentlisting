import 'dart:convert';

import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_engine.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  test(
    'deletion suppresses merged IDs through refresh and backup restore',
    () async {
      final document = indexDocument(['Arachnids live here.']);
      var source = [
        IndexEntity(id: 'a', kind: IndexKind.fossil, name: 'Arachnids'),
        IndexEntity(id: 'b', kind: IndexKind.fossil, name: 'Arachnids'),
      ];
      final store = MemoryIndexStore();
      KnowledgeIndexController controllerFor(MemoryIndexStore store) =>
          KnowledgeIndexController(
            catalogue: indexCatalogue(document),
            store: store,
            available: (_) => true,
            loadTranscript: (_) async => document,
            vocabulary: () async => IndexEntity.encode([]),
            enableHeuristicSuggestions: false,
            contextualIndex: () async => IndexEntity.encode(source),
          );
      final controller = controllerFor(store);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.entities, hasLength(1));
      final id = controller.entities.single.id;
      await controller.deleteEntity(
        id,
        expectedRevision: controller.registryRevision!,
      );
      expect(controller.entities, isEmpty);
      final tombstone = IndexEntity.decode(controller.exportDocument).single;
      expect(tombstone.deleted, isTrue);
      expect(tombstone.variantIds, contains('b'));
      expect(indexOccurrences(tombstone, [document]), isEmpty);
      source = [
        source.first,
        IndexEntity(id: 'b', kind: IndexKind.place, name: 'Arachnids'),
      ];
      await controller.refresh();
      expect(controller.entities, isEmpty);
      expect(controller.error, isNull);
      final restored = MemoryIndexStore();
      await restored.save(controller.exportDocument, expected: null);
      final restarted = controllerFor(restored);
      addTearDown(restarted.dispose);
      await restarted.refresh();
      expect(restarted.entities, isEmpty);
      expect(
        IndexEntity.decode(restarted.exportDocument).single.deleted,
        isTrue,
      );
    },
  );

  test(
    'deleting an author removes links and does not resurrect on refresh',
    () async {
      final document = indexDocument(['Named Author published research.']);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        enableHeuristicSuggestions: false,
        contextualIndex: () async => IndexEntity.encode([
          IndexEntity(
            id: 'author',
            kind: IndexKind.author,
            name: 'Named Author',
          ),
          IndexEntity(
            id: 'paper',
            kind: IndexKind.paper,
            name: 'Research',
            authorIds: ['author'],
          ),
        ]),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.deleteEntity(
        'author',
        expectedRevision: controller.registryRevision!,
      );
      expect(controller.entities.single.id, 'paper');
      expect(controller.entities.single.authorIds, isEmpty);
      expect(controller.entities.single.note, contains('deletion'));
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.entities.single.id, 'paper');
      expect(controller.entities.single.authorIds, isEmpty);
    },
  );

  test(
    'stale or conflicting deletion never overwrites other changes',
    () async {
      final document = indexDocument(['Arachnids.']);
      final store = MemoryIndexStore();
      final entry = IndexEntity(
        id: 'a',
        kind: IndexKind.fossil,
        name: 'Arachnids',
      );
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([entry]),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      final old = store.document;
      await expectLater(
        controller.deleteEntity('a', expectedRevision: 'stale'),
        throwsStateError,
      );
      expect(store.document, old);
      final external = IndexEntity.encode([
        IndexEntity(id: 'a', kind: IndexKind.fossil, name: 'Human correction'),
      ]);
      await store.save(external, expected: old);
      await expectLater(
        controller.deleteEntity(
          'a',
          expectedRevision: controller.registryRevision!,
        ),
        throwsStateError,
      );
      expect(store.document, external);
      expect(controller.entities.any((e) => e.id == 'a'), isTrue);
    },
  );

  test('deleted flag is strictly typed and preserved in exports', () {
    final e = IndexEntity(
      id: 'a',
      kind: IndexKind.fossil,
      name: 'Arachnids',
      deleted: true,
    );
    expect(IndexEntity.decode(IndexEntity.encode([e])).single.deleted, isTrue);
    final raw = e.toJson()..['deleted'] = 'true';
    expect(
      () => IndexEntity.decode(
        jsonEncode({
          'schema_version': 1,
          'entries': [raw],
        }),
      ),
      throwsFormatException,
    );
  });
}
