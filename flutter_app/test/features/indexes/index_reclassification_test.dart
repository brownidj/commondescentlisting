import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_entity_dialog.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

IndexEntity mistakenAuthor() => IndexEntity(
  id: 'local:opossum',
  kind: IndexKind.author,
  name: 'Didelphys virginiana',
  subtype: 'person',
  aliases: const ['Didelphys virginiana'],
  details: const IndexDetails(description: 'Original extraction evidence.'),
  anchors: const [
    IndexAnchor(
      guid: 'episode',
      edition: 'one',
      passageId: 1,
      quote: 'Didelphys virginiana',
      passageText: 'Didelphys virginiana.',
    ),
  ],
);
IndexEntity paper() => IndexEntity(
  id: 'paper',
  kind: IndexKind.paper,
  name: 'Study',
  authorIds: const ['local:opossum'],
  details: const IndexDetails(),
);

void main() {
  testWidgets(
    'existing entry can change index and classification without losing evidence',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      IndexEntity? saved;
      final original = mistakenAuthor();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showDialog<IndexEntity>(
                    context: context,
                    builder: (_) => IndexEntityDialog(
                      kind: IndexKind.author,
                      entity: original,
                      entities: [original, paper()],
                    ),
                  );
                },
                child: const Text('Review'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<IndexKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taxonomy').last);
      await tester.pumpAndSettle();
      final classification = find.widgetWithText(
        TextFormField,
        'Classification',
      );
      expect(
        tester.widget<TextFormField>(classification).controller!.text,
        isEmpty,
      );
      await tester.enterText(classification, 'extant species');
      expect(find.textContaining('Saving will remove'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.kind, IndexKind.fossil);
      expect(saved!.subtype, 'extant species');
      expect(saved!.id, original.id);
      expect(saved!.anchors, original.anchors);
      expect(saved!.details, original.details);
      expect(saved!.aliases, original.aliases);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'recategorisation persists through refresh/reload and repairs author links',
    () async {
      final document = indexDocument(['Didelphys virginiana.']);
      final store = MemoryIndexStore();
      KnowledgeIndexController make() => KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async =>
            IndexEntity.encode([mistakenAuthor(), paper()]),
        enableHeuristicSuggestions: false,
      );
      final controller = make();
      addTearDown(controller.dispose);
      await controller.refresh();
      final old = mistakenAuthor();
      await controller.saveEntity(
        IndexEntity(
          id: old.id,
          kind: IndexKind.fossil,
          name: old.name,
          subtype: 'extant species',
          aliases: old.aliases,
          anchors: old.anchors,
          details: old.details,
        ),
      );
      await controller.refresh();
      expect(controller.error, isNull);
      final entry = controller.entities.singleWhere((e) => e.id == old.id);
      expect(entry.kind, IndexKind.fossil);
      expect(entry.subtype, 'extant species');
      expect(controller.occurrences[old.id], hasLength(1));
      final publication = controller.entities.singleWhere(
        (e) => e.id == 'paper',
      );
      expect(publication.authorIds, isEmpty);
      expect(publication.note, contains('Review author attribution'));
      final restarted = make();
      addTearDown(restarted.dispose);
      await restarted.refresh();
      expect(restarted.error, isNull);
      expect(
        restarted.entities.singleWhere((e) => e.id == old.id).kind,
        IndexKind.fossil,
      );
      expect(
        restarted.entities.singleWhere((e) => e.id == 'paper').authorIds,
        isEmpty,
      );
    },
  );
}
