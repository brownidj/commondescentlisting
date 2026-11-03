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
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha details'), findsOneWidget);
    await tester.tap(find.text('Beta', findRichText: false).last);
    await tester.pumpAndSettle();
    expect(find.text('Alpha details'), findsNothing);
    expect(find.text('Beta details'), findsOneWidget);
    await tester.tap(find.text('Beta', findRichText: false).last);
    await tester.pumpAndSettle();
    expect(find.text('Beta details'), findsNothing);
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Beta');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta', findRichText: false).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Alpha details'), findsNothing);
    expect(find.text('Beta details'), findsOneWidget);
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
