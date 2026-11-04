import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_details_panel.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';

void main() {
  const anchor = IndexAnchor(
    guid: 'episode',
    edition: 'edition',
    passageId: 1,
    passageText: 'Mammalia lived here.',
    quote: 'Mammalia',
  );
  IndexEntity confirmed() => IndexEntity(
    id: 'taxon',
    kind: IndexKind.fossil,
    name: 'Mammalia',
    anchors: [anchor],
    details: IndexDetails(
      externalConfirmation: jsonEncode({
        'status': 'confirmed',
        'name': 'Mammalia',
        'kind': 'fossil',
        'sources': ['pbdb', 'col'],
        'evidence': [
          {
            'guid': anchor.guid,
            'edition': anchor.edition,
            'passage_id': anchor.passageId,
            'passage_text': anchor.passageText,
            'quote': anchor.quote,
          },
        ],
      }),
    ),
  );
  test('external confirmation round-trips independently of human review', () {
    final entity = IndexEntity.decode(IndexEntity.encode([confirmed()])).single;
    expect(entity.externallyConfirmed, isTrue);
    expect(entity.review, IndexReview.suggested);
    expect(entity.externalConfirmationSources, ['PBDB', 'Catalogue of Life']);
    expect(
      indexEntryTooltip(entity),
      contains('Confirmed by external sources'),
    );
  });
  test('editing identity or replacing supporting evidence invalidates confirmation', () {
    for (final field in ['name', 'kind', 'anchors']) {
      final value = confirmed().toJson();
      value[field] = field == 'name'
          ? 'Listener heading'
          : field == 'kind'
          ? 'place'
          : [];
      final entity = IndexEntity.decode(
        jsonEncode({
          'schema_version': 1,
          'entries': [value],
        }),
      ).single;
      expect(entity.externallyConfirmed, isFalse);
    }
  });
}
