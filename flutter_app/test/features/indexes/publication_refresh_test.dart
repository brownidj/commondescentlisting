import 'dart:convert';

import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_deletion_blacklist.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  test('sourced publication update preserves authors until full registry validation', () async {
    final document = indexDocument(['A study by First et al.']);
    final original = IndexEntity(
      id: 'paper',
      kind: IndexKind.paper,
      name: 'Study attributed to First et al.',
    );
    const metadata = [
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
    ];
    final before = original.toJson();
    final details = IndexDetails(
      refinementSource: jsonEncode({
        for (final key in metadata) key: before[key],
      }),
      bibliography: '{"status":"source_confirmed","title":"The sourced title"}',
      refinementReview: '{"model":"saved-provenance"}',
    );
    final enriched = IndexEntity(
      id: 'paper',
      kind: IndexKind.paper,
      name: 'The sourced title',
      authorIds: ['second', 'first'],
      details: details,
      variantIds: ['source-variant'],
    );
    final authors = [
      IndexEntity(id: 'first', kind: IndexKind.author, name: 'First Author'),
      IndexEntity(id: 'second', kind: IndexKind.author, name: 'Second Author'),
    ];
    final store = MemoryIndexStore()..document = IndexEntity.encode([original]);
    final controller = KnowledgeIndexController(
      catalogue: indexCatalogue(document),
      store: store,
      available: (_) => true,
      loadTranscript: (_) async => document,
      vocabulary: () async => IndexEntity.encode([]),
      contextualIndex: () async => IndexEntity.encode([enriched, ...authors]),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.error, isNull);
    expect(controller.ready, isTrue);
    final paper = controller.entities.singleWhere((e) => e.id == 'paper');
    expect(paper.name, 'The sourced title');
    expect(paper.authorIds, ['second', 'first']);
    expect(paper.variantIds, contains('source-variant'));
    expect(paper.details!.bibliography, details.bibliography);
    expect(paper.details!.refinementReview, details.refinementReview);
    expect(IndexEntity.decode(store.document!), hasLength(3));
    await controller.refresh();
    expect(controller.error, isNull);
    expect(controller.entities.singleWhere((e) => e.id == 'paper').authorIds, [
      'second',
      'first',
    ]);
  });

  test(
    'blacklisting a publication preserves linked author graph and metadata',
    () {
      final details = const IndexDetails(
        bibliography: '{"title":"Publication"}',
      );
      final paper = IndexEntity(
        id: 'new-paper',
        kind: IndexKind.paper,
        name: 'Publication',
        authorIds: ['author'],
        details: details,
        variantIds: ['earlier-paper'],
      );
      final author = IndexEntity(
        id: 'author',
        kind: IndexKind.author,
        name: 'An Author',
      );
      final blacklist = IndexDeletionBlacklist([
        IndexEntity(
          id: 'deleted-paper',
          kind: IndexKind.paper,
          name: 'Publication',
          deleted: true,
        ),
      ]);
      final result = blacklist.apply([paper, author]);
      expect(result.first.deleted, isTrue);
      expect(result.first.authorIds, ['author']);
      expect(result.first.details, same(details));
      expect(result.first.variantIds, ['earlier-paper']);
      expect(paper.deleted, isFalse);
      expect(IndexEntity.decode(IndexEntity.encode(result)), hasLength(2));
      // Keep rejecting a genuinely incomplete registry at the import boundary.
      expect(
        () => IndexEntity.decode(IndexEntity.encode([paper])),
        throwsFormatException,
      );
    },
  );
}
