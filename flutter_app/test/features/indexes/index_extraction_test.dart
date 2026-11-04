import 'dart:convert';

import 'package:common_descent_listing/features/indexes/index_details_panel.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_word_forms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> document({bool evidence = true}) => {
    'schema_version': 1,
    'entries': [
      {
        'id': 'fixture',
        'kind': 'fossil',
        'name': 'Bivalve',
        'anchors': [
          {
            'guid': 'episode',
            'edition': 'edition',
            'passage_id': 1,
            'passage_text': '🦕 Bivalve here.',
            'quote': 'Bivalve',
            if (evidence)
              'extraction': [
                {
                  'method': 'gliner',
                  'label': 'animal group',
                  'score': 0.75,
                  'start': 2,
                  'end': 9,
                  'offset_unit': 'unicode_code_points',
                  'extractor_version': 'local-index-2/gliner-fixture',
                  'model': 'fixture-model',
                  'model_revision': 'fixture-revision',
                },
              ],
          },
        ],
      },
    ],
  };

  test(
    'Unicode provenance survives registry round trip and remains suggested',
    () {
      final entries = IndexEntity.decode(jsonEncode(document()));
      final restored = IndexEntity.decode(IndexEntity.encode(entries));
      final anchor = restored.single.anchors.single;
      expect(anchor.extraction.single.start, 2);
      expect(anchor.extraction.single.score, .75);
      expect(anchor.extraction.single.modelRevision, 'fixture-revision');
      expect(restored.single.review, IndexReview.suggested);
      expect(indexEntryTooltip(restored.single), contains('model score 0.750'));
      expect(
        indexEntryTooltip(restored.single),
        contains('not human confirmation'),
      );
      expect(restored.single.toJson(), entries.single.toJson());
    },
  );

  test('legacy anchors remain readable', () {
    expect(
      IndexEntity.decode(jsonEncode(document(evidence: false)))
          .single
          .anchors
          .single
          .extraction,
      isEmpty,
    );
  });

  test('invalid score, offset unit or nonliteral Unicode span is refused', () {
    for (final change in [
      {'score': 1.5},
      {'start': 3},
      {'offset_unit': 'utf16'},
      {'extractor_version': ''},
    ]) {
      final data = document();
      final source = data['entries'][0]['anchors'][0]['extraction'][0] as Map;
      source.addAll(change);
      expect(() => IndexEntity.decode(jsonEncode(data)), throwsFormatException);
    }
  });

  test('duplicate entry merge preserves extraction evidence', () {
    final withEvidence = IndexEntity.decode(jsonEncode(document())).single;
    final without = IndexEntity.decode(jsonEncode(document(evidence: false)))
        .single
        .toJson();
    without['id'] = 'other';
    final second = IndexEntity.decode(
      jsonEncode({
        'schema_version': 1,
        'entries': [without],
      }),
    ).single;
    final merged = mergeIndexWordForms([withEvidence, second]);
    expect(merged, hasLength(1));
    expect(merged.single.anchors.expand((a) => a.extraction), hasLength(1));
  });
}
