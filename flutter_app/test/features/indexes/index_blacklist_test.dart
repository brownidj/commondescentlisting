import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_deletion_blacklist.dart';
import 'package:common_descent_listing/features/indexes/index_heading.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  test('omit The/the from filing headings, preserving source wording', () {
    expect(indexHeading('The Example'), 'Example');
    expect(indexHeading('the example'), 'example');
    expect(indexHeading('Therapsida'), 'Therapsida');
    expect(indexHeading('Example, The'), 'Example');
    final entity = IndexEntity(
      id: 'one',
      kind: IndexKind.place,
      name: 'The Example',
    );
    expect(entity.heading, 'Example');
    expect(entity.toJson()['name'], 'The Example');
  });

  test(
    'blacklist blocks exact regenerated headings, aliases and merged IDs',
    () {
      final blacklist = IndexDeletionBlacklist([
        IndexEntity(
          id: 'old',
          kind: IndexKind.place,
          name: 'The Example',
          aliases: ['Example alias'],
          variantIds: ['merged'],
          deleted: true,
        ),
      ]);
      IndexEntity entry(
        String id,
        String name, [
        IndexKind kind = IndexKind.place,
      ]) => IndexEntity(id: id, kind: kind, name: name);
      expect(blacklist.blocks(entry('new', 'example, the')), isTrue);
      expect(blacklist.blocks(entry('new', 'Example alias')), isTrue);
      expect(
        blacklist.blocks(entry('merged', 'Renamed', IndexKind.author)),
        isTrue,
      );
      expect(
        blacklist.blocks(entry('new', 'The Example', IndexKind.paper)),
        isFalse,
      );
      expect(blacklist.blocks(entry('new', 'Example Island')), isFalse);
    },
  );

  test(
    'deletions survive changed source IDs, restart and registry replacement',
    () async {
      final document = indexDocument(['The Example.']);
      final store = MemoryIndexStore();
      var sourceId = 'old';
      KnowledgeIndexController makeController() => KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([
          IndexEntity(id: sourceId, kind: IndexKind.place, name: 'The Example'),
        ]),
      );
      final first = makeController();
      await first.refresh();
      await first.deleteEntity(
        'old',
        expectedRevision: first.registryRevision!,
      );
      first.dispose();
      sourceId = 'regenerated';
      final restarted = makeController();
      addTearDown(restarted.dispose);
      await restarted.refresh();
      expect(restarted.entities, isEmpty);
      await restarted.replaceRegistry(
        IndexEntity.encode([
          IndexEntity(
            id: 'imported',
            kind: IndexKind.place,
            name: 'Example, The',
          ),
        ]),
      );
      expect(restarted.entities, isEmpty);
      expect(
        IndexEntity.decode(store.document!)
            .any((e) => e.id == 'old' && e.deleted),
        isTrue,
      );
      await restarted.refresh();
      expect(restarted.entities, isEmpty);
    },
  );
}
