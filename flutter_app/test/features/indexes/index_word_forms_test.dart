import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_engine.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_reference_ranges.dart';
import 'package:common_descent_listing/features/indexes/index_word_forms.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

IndexEntity entry(
  String name, {
  String subtype = 'organism_group',
  IndexReview review = IndexReview.suggested,
  List<IndexAnchor> anchors = const [],
}) => IndexEntity(
  id: name,
  kind: IndexKind.fossil,
  name: name,
  subtype: subtype,
  review: review,
  anchors: anchors,
  details: IndexDetails(
    spoken: [name],
    description: 'About $name',
    confidence: 'high',
  ),
);

void main() {
  test('controller refresh preserves singular heading, review and both source passages', () async {
    final document = indexDocument(['A bivalve.', 'Some bivalves.']);
    IndexAnchor anchor(int i) => IndexAnchor(
      guid: 'episode',
      edition: 'one',
      passageId: i + 1,
      quote: document.transcript.cues[i].text,
      passageText: document.transcript.cues[i].text,
    );
    final controller = KnowledgeIndexController(
      catalogue: indexCatalogue(document),
      store: MemoryIndexStore(),
      available: (_) => true,
      loadTranscript: (_) async => document,
      vocabulary: () async => IndexEntity.encode([]),
      enableHeuristicSuggestions: false,
      contextualIndex: () async => IndexEntity.encode([
        entry('bivalve', anchors: [anchor(0)]),
        entry('bivalves', anchors: [anchor(1)]),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.entities.single.name, 'bivalve');
    final saved = jsonDecode(controller.exportDocument) as Map<String, dynamic>;
    saved['entries'][0]['review'] = 'confirmed';
    saved['entries'][0]['name'] = 'Reviewed bivalve heading';
    await controller.replaceRegistry(jsonEncode(saved));
    await controller.refresh();
    expect(controller.entities.single.name, 'Reviewed bivalve heading');
    expect(controller.entities.single.review, IndexReview.confirmed);
    expect(controller.occurrences['bivalve'], hasLength(2));
    expect(controller.error, isNull);
  });
  test('singular heading retains both forms, metadata and unique passage references', () {
    final document = indexDocument([
      'A bivalve and bivalves.',
      'More bivalves.',
    ]);
    IndexAnchor anchor(int i, String quote) => IndexAnchor(
      guid: 'episode',
      edition: 'one',
      passageId: i + 1,
      passageText: document.transcript.cues[i].text,
      quote: quote,
    );
    final merged = mergeIndexWordForms([
      entry('bivalve', anchors: [anchor(0, 'bivalve')]),
      entry(
        'bivalves',
        anchors: [anchor(0, 'bivalves'), anchor(1, 'bivalves')],
      ),
    ]).single;
    expect(merged.name, 'bivalve');
    expect(merged.aliases, contains('bivalves'));
    expect(merged.details!.spoken, ['bivalve', 'bivalves']);
    expect(merged.details!.description, contains('About bivalves'));
    expect(merged.anchors, hasLength(3));
    final hits = indexOccurrences(merged, [document]);
    expect(hits.map((o) => o.cue.id), [1, 2]);
    expect(groupIndexReferences(hits).single.label, 'Passages 1–2');
  });

  test(
    'does not alter genus names, plural-only headings or conflicting decisions',
    () {
      expect(mergeIndexWordForms([entry('bivalves')]).single.name, 'bivalves');
      expect(
        mergeIndexWordForms([
          entry('Equus', subtype: 'genus'),
          entry('Equuses', subtype: 'genus'),
        ]),
        hasLength(2),
      );
      expect(
        mergeIndexWordForms([
          entry('bivalve'),
          entry('bivalves', review: IndexReview.rejected),
        ]),
        hasLength(2),
      );
    },
  );

  test(
    'merged membership and review survive backup and fresh plural suggestions',
    () {
      final merged = mergeIndexWordForms([entry('bivalve'), entry('bivalves')]);
      final raw =
          jsonDecode(IndexEntity.encode(merged)) as Map<String, dynamic>;
      raw['entries'][0]['review'] = 'confirmed';
      raw['entries'][0]['name'] = 'Reviewed bivalve heading';
      final saved = IndexEntity.decode(jsonEncode(raw));
      final refreshed = mergeIndexWordForms([...saved, entry('bivalves')]);
      expect(refreshed, hasLength(1));
      expect(refreshed.single.name, 'Reviewed bivalve heading');
      expect(refreshed.single.review, IndexReview.confirmed);
      expect(refreshed.single.variantIds, ['bivalves']);
      expect(
        mergeIndexWordForms(refreshed).single.toJson(),
        refreshed.single.toJson(),
      );
    },
  );

  test(
    'actual compiled bivalve entries form one heading without losing evidence',
    () {
      final source = IndexEntity.decode(
        File('assets/data/contextual_indexes.json').readAsStringSync(),
      );
      final originals = source
          .where((e) => ['bivalve', 'bivalves'].contains(e.name))
          .toList();
      final merged = mergeIndexWordForms(source);
      expect(merged.where((e) => e.name == 'bivalves'), isEmpty);
      final bivalve = merged.singleWhere((e) => e.name == 'bivalve');
      expect(
        bivalve.anchors.length,
        originals.fold<int>(0, (n, e) => n + e.anchors.length),
      );
      expect(bivalve.anchors.map((a) => a.guid).toSet(), hasLength(2));
    },
  );
}
