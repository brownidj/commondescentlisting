import 'dart:io';
import 'dart:convert';

import 'package:common_descent_listing/features/indexes/index_details.dart';

import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  test('API changes update only untouched suggested metadata', () async {
    final document = indexDocument(['Didelphys virginiana.']);
    final original = IndexEntity(
      id: 'species',
      kind: IndexKind.author,
      name: 'Didelphys virginiana',
      note: 'Local suggestion.',
    );
    final keys = {
      'name',
      'kind',
      'review',
      'aliases',
      'subtype',
      'year',
      'publication',
      'doi',
      'url',
      'link_verified',
      'author_ids',
      'note',
    };
    final snapshot = jsonEncode(
      Map.fromEntries(
        original.toJson().entries.where((e) => keys.contains(e.key)),
      ),
    );
    final revised = IndexEntity(
      id: original.id,
      kind: IndexKind.fossil,
      name: original.name,
      note: 'API reviewed.',
      details: IndexDetails(refinementSource: snapshot),
    );
    for (final saved in [
      original,
      IndexEntity(
        id: original.id,
        kind: IndexKind.author,
        name: original.name,
        note: original.note,
        review: IndexReview.confirmed,
      ),
      IndexEntity(
        id: original.id,
        kind: IndexKind.author,
        name: 'User correction',
        note: original.note,
      ),
      IndexEntity(
        id: original.id,
        kind: IndexKind.author,
        name: original.name,
        note: original.note,
        review: IndexReview.rejected,
      ),
    ]) {
      final store = MemoryIndexStore();
      await store.save(IndexEntity.encode([saved]), expected: null);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        enableHeuristicSuggestions: false,
        contextualIndex: () async => IndexEntity.encode([revised]),
      );
      await controller.refresh();
      expect(controller.error, isNull);
      final result = controller.entities.single;
      expect(
        result.kind,
        identical(saved, original) ? IndexKind.fossil : saved.kind,
      );
      expect(result.review, saved.review);
      expect(result.name, saved.name);
      expect(result.details!.refinementSource, snapshot);
      controller.dispose();
    }
  });

  test('refinement and enrichment snapshots preserve user changes', () async {
    final document = indexDocument(['Didelphys virginiana.']);
    final local = IndexEntity(
      id: 'species',
      kind: IndexKind.author,
      name: 'Didelphys virginiana',
    );
    final refined = IndexEntity(
      id: 'species',
      kind: IndexKind.fossil,
      name: 'Didelphys virginiana',
    );
    const keys = {
      'name',
      'kind',
      'review',
      'aliases',
      'subtype',
      'year',
      'publication',
      'doi',
      'url',
      'link_verified',
      'author_ids',
      'note',
    };
    final snapshots = jsonEncode([
      for (final entry in [local, refined])
        Map.fromEntries(
          entry.toJson().entries.where((e) => keys.contains(e.key)),
        ),
    ]);
    final enriched = IndexEntity(
      id: 'species',
      kind: IndexKind.fossil,
      name: 'Didelphis virginiana',
      details: IndexDetails(refinementSource: snapshots),
    );
    final edited = IndexEntity(
      id: 'species',
      kind: IndexKind.fossil,
      name: 'Listener heading',
    );
    for (final saved in [local, refined, edited]) {
      final store = MemoryIndexStore();
      await store.save(IndexEntity.encode([saved]), expected: null);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        enableHeuristicSuggestions: false,
        contextualIndex: () async => IndexEntity.encode([enriched]),
      );
      await controller.refresh();
      expect(controller.error, isNull);
      expect(
        controller.entities.single.name,
        identical(saved, edited) ? 'Listener heading' : 'Didelphis virginiana',
      );
      controller.dispose();
    }
  });

  test('review decisions survive corrections and retranscription; occurrences are rebuilt', () async {
    var document = indexDocument(['Elasmosaurus lived here.']);
    final store = MemoryIndexStore();
    final controller = KnowledgeIndexController(
      catalogue: indexCatalogue(document),
      store: store,
      available: (_) => true,
      loadTranscript: (_) async => document,
      vocabulary: () async => IndexEntity.encode([
        IndexEntity(id: 'elas', kind: IndexKind.fossil, name: 'Elasmosaurus'),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.occurrences['elas'], hasLength(1));
    await controller.saveEntity(
      IndexEntity(
        id: 'elas',
        kind: IndexKind.fossil,
        name: 'Elasmosaurus',
        review: IndexReview.confirmed,
      ),
    );
    document = indexDocument(['A corrected different name.'], edition: 'two');
    await controller.refresh();
    expect(
      controller.entities.singleWhere((e) => e.id == 'elas').review,
      IndexReview.confirmed,
    );
    expect(controller.occurrences['elas'], isEmpty);
  });
  test(
    'stale editions/text refuse navigation; current nudge is used for playback',
    () async {
      var document = indexDocument([
        'First',
        'Karoo',
      ], offset: const Duration(milliseconds: 500));
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
      );
      addTearDown(controller.dispose);
      final occurrence = (document: document, cue: document.transcript.cues[1]);
      document = indexDocument([
        'First',
        'Karoo',
      ], offset: const Duration(seconds: 1));
      final fresh = await controller.resolve(occurrence);
      expect(fresh.document.audioStart(fresh.cue), const Duration(seconds: 4));
      document = indexDocument(['First', 'Corrected']);
      await expectLater(controller.resolve(occurrence), throwsStateError);
      document = indexDocument(['First', 'Karoo'], edition: 'two');
      await expectLater(controller.resolve(occurrence), throwsStateError);
    },
  );
  test(
    'failed loads are reported; persistence conflicts preserve saved decisions',
    () async {
      final d = indexDocument(['Karoo']);
      final store = MemoryIndexStore();
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(d),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async =>
            throw StateError('Corrections cannot be read'),
        vocabulary: () async => IndexEntity.encode([]),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(
        controller.loadFailures.single,
        contains('Corrections cannot be read'),
      );
      final saved = store.document;
      store.refuse = true;
      await expectLater(
        controller.saveEntity(
          IndexEntity(id: 'new', kind: IndexKind.place, name: 'Karoo'),
        ),
        throwsStateError,
      );
      expect(store.document, saved);
      expect(controller.entities, isEmpty);
    },
  );
  test('file registry compare-and-swap rejects stale writes and survives reopening', () async {
    final temp = await Directory.systemTemp.createTemp(
      'transcript-index-test-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final first = FileIndexRegistryStore(directory: () async => temp);
    final second = FileIndexRegistryStore(directory: () async => temp);
    expect(await first.save('first', expected: null), isTrue);
    expect(await second.read(), 'first');
    expect(await second.save('stale', expected: null), isFalse);
    expect(await first.read(), 'first');
    expect(await second.save('second', expected: 'first'), isTrue);
    expect(await first.read(), 'second');
  });
}
