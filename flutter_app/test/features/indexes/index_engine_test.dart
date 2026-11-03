import 'dart:convert';

import 'package:common_descent_listing/features/indexes/index_engine.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  test('whole names, aliases, Unicode boundaries and one hit per passage', () {
    final e = IndexEntity(
      id: 'fossil',
      kind: IndexKind.fossil,
      name: 'Elasmosaurus',
      aliases: ['Elasmosaurs'],
    );
    final d = indexDocument([
      'ELASMOSAURUS and elasmosaurs.',
      'Elasmosauruslike',
      'éElasmosaurus',
      'Elasmosaurs again.',
    ]);
    expect(indexOccurrences(e, [d]).map((o) => o.cue.id), [1, 4]);
    final place = IndexEntity(
      id: 'place',
      kind: IndexKind.place,
      name: 'Karoo–Ferrar',
    );
    expect(
      indexOccurrences(place, [
        indexDocument(['Karoo-Ferrar province']),
      ]),
      hasLength(1),
    );
  });
  test(
    'review rejection suppresses hits; anchors do not guess new wording',
    () {
      final rejected = IndexEntity(
        id: 'x',
        kind: IndexKind.place,
        name: 'Karoo',
        review: IndexReview.rejected,
      );
      expect(
        indexOccurrences(rejected, [
          indexDocument(['Karoo']),
        ]),
        isEmpty,
      );
      final ref = IndexEntity(
        id: 'ref',
        kind: IndexKind.paper,
        name: 'Untitled paper',
        anchors: const [
          IndexAnchor(
            guid: 'episode',
            quote: 'This is research by Jane Smith.',
          ),
        ],
      );
      expect(
        indexOccurrences(ref, [
          indexDocument(['Other', 'This is research by Jane Smith.']),
        ]).single.cue.id,
        2,
      );
      expect(
        indexOccurrences(ref, [
          indexDocument(['This is research by Janet Smith.']),
        ]),
        isEmpty,
      );
    },
  );
  test('proposals keep publication titles and metadata unknown, with role-specific authors', () {
    final d = indexDocument([
      'This is research by Jane Smith in the journal Science. The article is by Emily Jones.',
      'The species Elasmosaurus platyurus was found in South Africa.',
    ]);
    final entries = suggestIndexEntries([d]);
    final paper = entries.singleWhere((e) => e.kind == IndexKind.paper);
    final article = entries.singleWhere((e) => e.kind == IndexKind.article);
    expect(paper.name, startsWith('Untitled paper'));
    expect(paper.authorIds, ['author:jane smith']);
    expect(article.authorIds, ['author:emily jones']);
    expect(paper.year, isNull);
    expect(paper.publication, isEmpty);
    expect(
      entries.every(
        (e) => e.review == IndexReview.suggested && !e.linkVerified,
      ),
      isTrue,
    );
    expect(entries.any((e) => e.name == 'Elasmosaurus platyurus'), isTrue);
    expect(entries.any((e) => e.name == 'South Africa'), isTrue);
  });
  test(
    'shared authors retain publication order and reject dangling references',
    () {
      final authors = [
        IndexEntity(id: 'a', kind: IndexKind.author, name: 'Jane Smith'),
        IndexEntity(id: 'b', kind: IndexKind.author, name: 'Emily Jones'),
      ];
      final paper = IndexEntity(
        id: 'p',
        kind: IndexKind.paper,
        name: 'Research',
        authorIds: ['b', 'a'],
      );
      final decoded = IndexEntity.decode(
        IndexEntity.encode([...authors, paper]),
      );
      expect(decoded.last.authorIds, ['b', 'a']);
      expect(
        () => IndexEntity.decode(IndexEntity.encode([paper])),
        throwsFormatException,
      );
      expect(
        () => IndexEntity.decode(
          IndexEntity.encode([authors.first, authors.first]),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'unsafe reference URLs and malformed schemas are rejected on import',
    () {
      for (final url in [
        'javascript:alert(1)',
        'file:///tmp/file',
        'https://user:password@example.com',
      ]) {
        final bad = IndexEntity(
          id: 'p',
          kind: IndexKind.paper,
          name: 'Paper',
          url: url,
          linkVerified: true,
        );
        expect(
          () => IndexEntity.decode(IndexEntity.encode([bad])),
          throwsFormatException,
        );
      }
      expect(
        () => IndexEntity.decode(
          jsonEncode({'schema_version': 2, 'entries': []}),
        ),
        throwsFormatException,
      );
      final ref = IndexEntity(
        id: 'p',
        kind: IndexKind.paper,
        name: 'Paper',
        doi: '10.1234/test',
      );
      expect(ref.verifiedUri, isNull);
    },
  );
}
