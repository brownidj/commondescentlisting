import 'package:common_descent_listing/data/local_prepared_episodes.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  IndexEntity entry({String edition = 'one'}) => IndexEntity(
    id: 'local:fixture',
    kind: IndexKind.fossil,
    name: 'Fossil',
    details: const IndexDetails(model: 'local'),
    anchors: [
      IndexAnchor(
        guid: 'episode',
        edition: edition,
        passageId: 1,
        quote: 'Fossil',
        passageText: 'Fossil here.',
      ),
    ],
  );
  test(
    'local suggestions load, preserve review decisions and reject stale text',
    () async {
      var document = indexDocument(['Fossil here.']);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        enableHeuristicSuggestions: false,
        localIndexes: () async => [entry()],
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.occurrences['local:fixture'], hasLength(1));
      await controller.replaceRegistry(
        IndexEntity.encode([
          IndexEntity(
            id: 'local:fixture',
            kind: IndexKind.fossil,
            name: 'Reviewed fossil',
            review: IndexReview.confirmed,
            details: entry().details,
            anchors: entry().anchors,
          ),
        ]),
      );
      await controller.refresh();
      expect(controller.entities.single.name, 'Reviewed fossil');
      expect(controller.entities.single.review, IndexReview.confirmed);
      document = indexDocument(['Changed words.']);
      await controller.refresh();
      expect(controller.occurrences['local:fixture'], isEmpty);
    },
  );
  test('same entity from bundled and server sources retains both passage references', () async {
    final document = indexDocument(['Fossil here.', 'Fossil again.']);
    final second = IndexEntity(
      id: entry().id,
      kind: IndexKind.fossil,
      name: 'Fossil',
      details: entry().details,
      anchors: const [
        IndexAnchor(
          guid: 'episode',
          edition: 'one',
          passageId: 2,
          quote: 'Fossil',
          passageText: 'Fossil again.',
        ),
      ],
    );
    final controller = KnowledgeIndexController(
      catalogue: indexCatalogue(document),
      store: MemoryIndexStore(),
      available: (_) => true,
      loadTranscript: (_) async => document,
      vocabulary: () async => IndexEntity.encode([]),
      enableHeuristicSuggestions: false,
      contextualIndex: () async => IndexEntity.encode([entry()]),
      localIndexes: () async => [second],
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.error, isNull);
    expect(controller.entities, hasLength(1));
    expect(controller.occurrences[entry().id], hasLength(2));
  });

  test('worker local indexes refuse a mismatched edition', () async {
    addTearDown(() => LocalPreparedEpisodes.replace([]));
    LocalPreparedEpisodes.replace([
      LocalPreparedEdition(
        guid: 'episode',
        edition: 'two',
        audioUri: Uri.parse('http://localhost/audio'),
        audioIdentity: 'sha256:fixture',
        duration: const Duration(seconds: 5),
        passageCount: 1,
        hasIndex: true,
        loadText: (_) async => IndexEntity.encode([entry()]),
      ),
    ]);
    await expectLater(loadLocalIndexEntries(), throwsFormatException);
  });
}
