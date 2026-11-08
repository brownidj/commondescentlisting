import 'package:common_descent_listing/features/indexes/index_addition_policy.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  IndexEntity entry(
    String name, {
    IndexKind kind = IndexKind.fossil,
    List<String> aliases = const [],
  }) => IndexEntity(id: 'new', kind: kind, name: name, aliases: aliases);

  test('blocks grammatical entries and aliases, allows meaningful phrases', () {
    for (final name in ['of', 'The', 'on', 'in the', 'and', '!!!']) {
      expect(
        indexAdditionProblem(entry(name), []),
        contains('cannot be added'),
      );
    }
    expect(indexAdditionProblem(entry('Gulf of Mexico'), []), isNull);
    expect(indexAdditionProblem(entry('Origin of Species'), []), isNull);
    expect(
      indexAdditionProblem(entry('Mexico', aliases: ['of']), []),
      isNotNull,
    );
  });

  test('deletion history blocks aliases, filing forms, plurals and category bypasses', () {
    final deleted = [
      IndexEntity(
        id: 'old',
        kind: IndexKind.place,
        name: 'The Pacific',
        aliases: ['Pacific Ocean'],
        deleted: true,
      ),
      IndexEntity(
        id: 'c',
        kind: IndexKind.fossil,
        name: 'Crocodile',
        deleted: true,
      ),
      IndexEntity(
        id: 'h',
        kind: IndexKind.fossil,
        name: 'herbivore animals',
        deleted: true,
      ),
    ];
    for (final name in [
      'Pacific, the',
      'Pacific Ocean',
      'Crocodiles',
      'animals, herbivore',
    ]) {
      expect(
        indexAdditionProblem(entry(name, kind: IndexKind.author), deleted),
        contains('deletion list'),
      );
    }
    expect(indexAdditionProblem(entry('Pacific island'), deleted), isNull);
  });

  test(
    'controller rejects a blocked addition without changing stored registry',
    () async {
      final document = indexDocument(['The Karoo.']);
      final store = MemoryIndexStore();
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([
          IndexEntity(
            id: 'old',
            kind: IndexKind.place,
            name: 'Karoo',
            deleted: true,
          ),
        ]),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      final saved = store.document;
      await expectLater(
        controller.saveEntity(entry('Karoo', kind: IndexKind.author)),
        throwsStateError,
      );
      await expectLater(controller.saveEntity(entry('of')), throwsStateError);
      expect(store.document, saved);
      expect(controller.entities, isEmpty);
    },
  );
}
