import 'package:common_descent_listing/features/indexes/index_browser.dart';
import 'package:common_descent_listing/features/indexes/index_controller.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'index_test_support.dart';

void main() {
  testWidgets(
    'checkboxes select without opening and bulk Delete requires Yes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = indexDocument(['Alpha and Beta.']);
      final store = MemoryIndexStore();
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: store,
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([
          IndexEntity(id: 'a', kind: IndexKind.place, name: 'Alpha'),
          IndexEntity(id: 'b', kind: IndexKind.place, name: 'Beta'),
          IndexEntity(id: 'c', kind: IndexKind.place, name: 'Gamma'),
        ]),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexBrowser(
              catalogue: controller.catalogue,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taxonomy').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Places').last);
      await tester.pumpAndSettle();
      final delete = find.widgetWithText(TextButton, 'Delete');
      bool enabled() => tester.widget<TextButton>(delete).onPressed != null;
      final alpha = find.byKey(const ValueKey('delete-index-a'));
      final beta = find.byKey(const ValueKey('delete-index-b'));
      expect(enabled(), isFalse);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(enabled(), isFalse);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(alpha);
      await tester.pumpAndSettle();
      expect(enabled(), isTrue);
      expect(find.text('Review entry / author links'), findsNothing);
      await tester.tap(alpha);
      await tester.pumpAndSettle();
      expect(enabled(), isFalse);
      await tester.tap(alpha);
      await tester.tap(beta);
      await tester.pumpAndSettle();
      expect(find.text('Review entry / author links'), findsNothing);
      final sort = find.widgetWithText(OutlinedButton, '↕ A–Z');
      expect(
        tester.getCenter(delete).dx,
        greaterThan(tester.getCenter(find.byTooltip('Import indexes')).dx),
      );
      expect(
        tester.getCenter(delete).dy,
        closeTo(tester.getCenter(sort).dy, 5),
      );
      final unchanged = store.document;
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(
        find.textContaining('Delete 2 marked index entries?'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'No'));
      await tester.pumpAndSettle();
      expect(store.document, unchanged);
      expect(enabled(), isTrue);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsNothing);
      expect(find.text('Gamma'), findsOneWidget);
      expect(enabled(), isFalse);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(controller.entities.map((e) => e.id), ['c']);
      expect(
        IndexEntity.decode(store.document!).where((e) => e.deleted),
        hasLength(2),
      );
      // Changing search clears marked entries before they become hidden.
      await tester.tap(find.byKey(const ValueKey('delete-index-c')));
      await tester.pumpAndSettle();
      expect(enabled(), isTrue);
      await tester.enterText(find.byType(TextField).first, 'Missing');
      await tester.pumpAndSettle();
      expect(enabled(), isFalse);
      await tester.tap(find.byTooltip('Clear index search'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('delete-index-c')))
            .value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'entry summary is compact and controls stay fixed while entries scroll',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = indexDocument(['Spoken evidence.']);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(document),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (_) async => document,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([
          for (var i = 0; i < 50; i++)
            IndexEntity(
              id: 'entry-$i',
              kind: IndexKind.fossil,
              name: 'Entry ${i.toString().padLeft(3, '0')}',
              subtype: 'organism_group',
              anchors: const [
                IndexAnchor(
                  guid: 'episode',
                  quote: 'Spoken evidence.',
                  passageId: 1,
                  edition: 'one',
                  passageText: 'Spoken evidence.',
                ),
              ],
              details: const IndexDetails(
                spoken: ['Spoken form'],
                description: 'Description in tooltip',
                confidence: 'high',
                editorialNote: 'Needs review',
                model: 'Extraction model name',
              ),
            ),
        ]),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexBrowser(
              catalogue: controller.catalogue,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('index-entry-info-entry-0')),
        findsNothing,
      );
      final item = find.byKey(const ValueKey('contextual-index-entry-0'));
      expect(
        find.descendant(
          of: item,
          matching: find.text('Taxonomy · 1 reference'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Entry 000'));
      await tester.pumpAndSettle();
      final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('index-entry-info-entry-0')),
      );
      expect(tooltip.message, contains('Spoken: Spoken form'));
      expect(tooltip.message, contains('Model confidence: high'));
      expect(tooltip.message, contains('Description in tooltip'));
      expect(tooltip.message, contains('Needs review'));
      expect(find.text('Description in tooltip'), findsNothing);
      expect(find.textContaining('Spoken:'), findsNothing);
      expect(find.textContaining('Taxonomy /'), findsNothing);
      final toolbar = find.byKey(const ValueKey('indexes-toolbar'));
      final headerPosition = tester.getTopLeft(toolbar);
      final importPosition = tester.getCenter(find.byTooltip('Import indexes'));
      final results = find.byKey(const PageStorageKey('knowledge-index-list'));
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(of: results, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      await tester.drag(results, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.getTopLeft(toolbar), headerPosition);
      expect(
        tester.getCenter(find.byTooltip('Import indexes')),
        importPosition,
      );
      expect(find.text('Indexes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all-entry and episode indexes retain categories and scoped references',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final first = indexDocument(['First episode evidence.']);
      final second = CurrentTranscript(
        episode: Episode(
          guid: 'second',
          title: 'Second episode',
          number: '83',
          segments: const [],
        ),
        edition: 'two',
        syncOffset: Duration.zero,
        transcript: EpisodeTranscript(
          episodeGuid: 'second',
          label: 'Fixture',
          note: '',
          audioIdentity: 'sha256:two',
          cues: [
            TranscriptCue(
              id: 1,
              start: Duration.zero,
              end: const Duration(seconds: 5),
              text: 'Second episode evidence.',
              originalText: 'Second episode evidence.',
              reviewNotes: const [],
            ),
          ],
        ),
      );
      IndexAnchor anchor(CurrentTranscript d) => IndexAnchor(
        guid: d.episode.guid,
        quote: d.transcript.cues.first.text,
        passageId: 1,
        edition: d.edition,
        passageText: d.transcript.cues.first.text,
      );
      final controller = KnowledgeIndexController(
        catalogue: Catalogue(
          podcast: const Podcast(title: 'Fixture'),
          episodes: [first.episode, second.episode],
          segments: const [],
          sourceName: 'fixture',
        ),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (e) async => e.guid == 'second' ? second : first,
        vocabulary: () async => IndexEntity.encode([]),
        contextualIndex: () async => IndexEntity.encode([
          IndexEntity(
            id: 'shared',
            kind: IndexKind.fossil,
            name: 'Shared fossil',
            anchors: [anchor(first), anchor(second)],
            details: const IndexDetails(),
          ),
          IndexEntity(
            id: 'second-only',
            kind: IndexKind.fossil,
            name: 'Second only',
            anchors: [anchor(second)],
            details: const IndexDetails(),
          ),
          IndexEntity(
            id: 'place',
            kind: IndexKind.place,
            name: 'First place',
            anchors: [anchor(first)],
            details: const IndexDetails(),
          ),
        ]),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexBrowser(
              catalogue: controller.catalogue,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final heading = tester.widget<Tooltip>(
        find.byKey(const ValueKey('index-heading-info')),
      );
      expect(heading.message, contains('Bundled catalogue'));
      expect(heading.message, contains('2 episodes · 0 news records'));
      expect(
        heading.message,
        contains('2 available transcripts · 2 with contextual index matches'),
      );
      expect(heading.message, contains('Expand an entry'));
      expect(find.textContaining('available transcripts'), findsNothing);
      expect(find.textContaining('Expand an entry'), findsNothing);
      final row = find.byKey(const ValueKey('index-filter-row'));
      final fields = find.descendant(
        of: row,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      final search = find.descendant(of: row, matching: find.byType(TextField));
      expect(fields, findsNWidgets(2));
      expect(
        tester.getTopLeft(fields.first).dy,
        closeTo(tester.getTopLeft(search).dy, 1),
      );
      expect(
        tester.getTopLeft(fields.last).dy,
        closeTo(tester.getTopLeft(search).dy, 1),
      );
      await tester.tap(find.text('↕ A–Z'));
      await tester.pumpAndSettle();
      expect(find.text('↕ Z–A'), findsOneWidget);
      expect(find.byIcon(Icons.sort_by_alpha), findsNothing);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('index-filter-row')), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(1000, 2000));
      await tester.pumpAndSettle();
      expect(find.text('Shared fossil'), findsOneWidget);
      expect(find.text('Second only'), findsOneWidget);
      await tester.tap(find.text('Shared fossil'));
      await tester.pumpAndSettle();
      expect(find.text('First episode evidence.'), findsOneWidget);
      expect(find.text('Second episode evidence.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('transcript-episode-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('208 — Sample episode').last);
      await tester.pumpAndSettle();
      expect(find.text('Second only'), findsNothing);
      await tester.tap(find.text('Shared fossil'));
      await tester.pumpAndSettle();
      expect(find.text('First episode evidence.'), findsOneWidget);
      expect(find.text('Second episode evidence.'), findsNothing);
      await tester.tap(find.text('Review entry / author links'));
      await tester.pumpAndSettle();
      expect(find.text('1 references in 1 episodes'), findsOneWidget);
      expect(find.text('Second episode evidence.'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Places').last);
      await tester.pumpAndSettle();
      expect(find.text('First place'), findsOneWidget);
      expect(find.text('208 — Sample episode'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('transcript-episode-episode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('83 — Second episode').last);
      await tester.pumpAndSettle();
      expect(find.text('First place'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('transcript-episode-second')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All entries').last);
      await tester.pumpAndSettle();
      expect(find.text('First place'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening another index entry closes the previous entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final document = indexDocument(['Sample passage.']);
    final controller = KnowledgeIndexController(
      catalogue: indexCatalogue(document),
      store: MemoryIndexStore(),
      available: (_) => true,
      loadTranscript: (_) async => document,
      vocabulary: () async => IndexEntity.encode([]),
      contextualIndex: () async => IndexEntity.encode([
        IndexEntity(
          id: 'alpha',
          kind: IndexKind.fossil,
          name: 'Alpha',
          details: const IndexDetails(description: 'Alpha details'),
        ),
        IndexEntity(
          id: 'beta',
          kind: IndexKind.fossil,
          name: 'Beta',
          details: const IndexDetails(description: 'Beta details'),
        ),
      ]),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IndexBrowser(
            catalogue: controller.catalogue,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder reviewAction(String id) => find.descendant(
      of: find.byKey(ValueKey('contextual-index-$id')),
      matching: find.text('Review entry / author links'),
    );
    expect(find.byKey(const ValueKey('index-entry-info-alpha')), findsNothing);
    expect(find.byKey(const ValueKey('index-entry-info-beta')), findsNothing);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(reviewAction('alpha'), findsOneWidget);
    expect(reviewAction('beta'), findsNothing);
    expect(find.text('Alpha details'), findsNothing);
    final tooltip = tester.widget<Tooltip>(
      find.byKey(const ValueKey('index-entry-info-alpha')),
    );
    expect(tooltip.message, contains('Alpha details'));
    await tester.tap(find.text('Beta', findRichText: false).last);
    await tester.pumpAndSettle();
    expect(reviewAction('alpha'), findsNothing);
    expect(reviewAction('beta'), findsOneWidget);
    expect(find.byKey(const ValueKey('index-entry-info-alpha')), findsNothing);
    expect(find.byKey(const ValueKey('index-entry-info-beta')), findsOneWidget);
    await tester.tap(find.text('Beta', findRichText: false).last);
    await tester.pumpAndSettle();
    expect(reviewAction('beta'), findsNothing);
    expect(find.byKey(const ValueKey('index-entry-info-beta')), findsNothing);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Beta');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta', findRichText: false).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(reviewAction('alpha'), findsNothing);
    expect(reviewAction('beta'), findsOneWidget);
    expect(find.byKey(const ValueKey('index-entry-info-alpha')), findsNothing);
    expect(find.byKey(const ValueKey('index-entry-info-beta')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'indexes show occurrences and persist an explicit review decision',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = indexDocument([
        'Elasmosaurus was found here.',
        'Another passage.',
      ]);
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
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexBrowser(
              catalogue: controller.catalogue,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Elasmosaurus'), findsOneWidget);
      await tester.tap(find.text('Elasmosaurus'));
      await tester.pumpAndSettle();
      expect(find.text('Passage 1 · 00:00:00'), findsOneWidget);
      expect(find.text('Open passage'), findsOneWidget);
      await tester.tap(find.text('Review entry / author links'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review / edit entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<IndexReview>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('confirmed').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(controller.entities.single.review, IndexReview.confirmed);
      expect(
        IndexEntity.decode(store.document!).single.review,
        IndexReview.confirmed,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'transcript search finds passages and exposes scope and sort controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final d = indexDocument(['The Karoo is extensive.', 'Other words.']);
      final controller = KnowledgeIndexController(
        catalogue: indexCatalogue(d),
        store: MemoryIndexStore(),
        available: (_) => true,
        loadTranscript: (_) async => d,
        vocabulary: () async => IndexEntity.encode([]),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IndexBrowser(
              catalogue: controller.catalogue,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transcripts').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'karoo');
      await tester.pumpAndSettle();
      expect(find.text('1 matching passages'), findsOneWidget);
      expect(find.text('Passage 1 · 00:00:00'), findsOneWidget);
      expect(find.text('Sort transcripts'), findsOneWidget);
      expect(find.text('Index scope'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
