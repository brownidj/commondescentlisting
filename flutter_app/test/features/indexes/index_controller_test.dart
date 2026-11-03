import 'dart:io';

import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
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
