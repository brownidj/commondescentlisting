import 'dart:convert';

import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/playback_preferences.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

Future<void> _selectAndOpenPassage(WidgetTester tester) async {
  final cue = find.byKey(const ValueKey('transcript-cue-2'));
  await tester.ensureVisible(cue);
  await tester.longPress(cue);
  await tester.pumpAndSettle();
  final edit = find.descendant(of: cue, matching: find.byType(IconButton));
  expect(edit, findsOneWidget);
  expect(tester.widget<IconButton>(edit).onPressed, isNotNull);
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

void main() {
  final episode = Episode(
    guid: editableTranscript.episodeGuid,
    title: 'Editable episode',
    number: '208',
    segments: [
      Segment(
        sourceIndex: 0,
        guid: editableTranscript.episodeGuid,
        episodeTitle: 'Editable episode',
        type: 'Episode',
        audioUrl: 'https://example.com/episode.mp3',
      ),
    ],
  );

  testWidgets('selected passage can be edited without a playback controller', (
    tester,
  ) async {
    final store = MemoryTranscriptEditStore();
    await tester.pumpWidget(
      MaterialApp(
        home: TranscriptPage(
          episode: episode,
          editStore: store,
          loadTranscript: (_) async => editableTranscript,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAndOpenPassage(tester);

    final field = find.byKey(const ValueKey('transcript-editor-text'));
    await tester.enterText(field, 'Saved without a player.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.documents.values.single, contains('Saved without a player.'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('episode changes wait until the open editor saves', (
    tester,
  ) async {
    final store = MemoryTranscriptEditStore();
    final nextEpisode = Episode(
      guid: 'next-editor-episode',
      title: 'Next episode',
      number: '209',
      segments: [],
    );
    var selectedEpisode = episode;
    late StateSetter updateParent;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateParent = setState;
            return TranscriptPage(
              episode: selectedEpisode,
              editStore: store,
              loadTranscript: (guid) async {
                if (guid == episode.guid) return editableTranscript;
                return EpisodeTranscript(
                  episodeGuid: guid,
                  label: 'Next episode transcript',
                  note: '',
                  cues: const [
                    TranscriptCue(
                      id: 1,
                      start: Duration.zero,
                      end: Duration(seconds: 10),
                      text: 'Next episode passage.',
                      originalText: 'Next episode passage.',
                      reviewNotes: [],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAndOpenPassage(tester);
    final field = find.byKey(const ValueKey('transcript-editor-text'));
    await tester.enterText(field, 'Saved before changing episodes.');

    updateParent(() => selectedEpisode = nextEpisode);
    await tester.pumpAndSettle();
    expect(field, findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      store.documents[episode.guid],
      contains('Saved before changing episodes.'),
    );
    expect(find.text('Next episode transcript'), findsOneWidget);
    expect(find.text('Next episode passage.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected passage can be edited with Apple Podcasts selected', (
    tester,
  ) async {
    final store = MemoryTranscriptEditStore();
    final player = PlaybackController(createEngine: FakeAudio.new);
    addTearDown(player.dispose);
    await player.setOutput(PlaybackOutput.applePodcasts);
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          home: TranscriptPage(
            episode: episode,
            editStore: store,
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAndOpenPassage(tester);
    final replay = find.widgetWithText(OutlinedButton, 'Replay passage');
    expect(tester.widget<OutlinedButton>(replay).onPressed, isNull);

    final field = find.byKey(const ValueKey('transcript-editor-text'));
    await tester.enterText(field, 'Saved with Apple Podcasts selected.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      store.documents.values.single,
      contains('Saved with Apple Podcasts selected.'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing and replay restore a different playing episode', (
    tester,
  ) async {
    final store = MemoryTranscriptEditStore();
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    final otherEpisode = Episode(
      guid: 'other-listening-episode',
      title: 'Other episode',
      number: '209',
      segments: const [
        Segment(
          sourceIndex: 0,
          guid: 'other-listening-episode',
          episodeTitle: 'Other episode',
          type: 'Episode',
          audioUrl: 'https://example.com/other.mp3',
        ),
      ],
    );
    await player.playEpisode(otherEpisode, from: const Duration(seconds: 25));
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          home: TranscriptPage(
            episode: episode,
            editStore: store,
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectAndOpenPassage(tester);
    expect(player.playing, isFalse);

    await tester.tap(find.text('Replay passage'));
    await tester.pumpAndSettle();
    expect(player.episode, episode);
    expect(player.position, const Duration(seconds: 10));
    expect(player.playing, isTrue);

    final field = find.byKey(const ValueKey('transcript-editor-text'));
    await tester.enterText(field, 'Saved after replay.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(player.episode, otherEpisode);
    expect(audio.source, otherEpisode.audioUri);
    expect(player.position, const Duration(seconds: 25));
    expect(player.playing, isTrue);
    expect(store.documents.values.single, contains('Saved after replay.'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected passage pencil pauses for editing without changing audio time or sync',
    (tester) async {
      final store = MemoryTranscriptEditStore();
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      await player.playEpisode(episode, from: const Duration(seconds: 4));
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            home: TranscriptPage(
              episode: episode,
              editStore: store,
              loadTranscript: (_) async => editableTranscript,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cue = find.byKey(const ValueKey('transcript-cue-2'));
      await tester.ensureVisible(cue);
      await tester.longPress(cue);
      await tester.pumpAndSettle();
      expect(find.byTooltip(RegExp(r'^Sync passage')), findsNothing);
      expect(find.text('Selected for editing'), findsNothing);
      expect(find.byTooltip('Edit passage 2'), findsOneWidget);
      expect(audio.position, const Duration(seconds: 4));
      expect(audio.playing, isTrue);
      await tester.tap(find.byTooltip('Edit passage 2'));
      await tester.pumpAndSettle();
      expect(find.text('Edit passage 2'), findsOneWidget);
      expect(audio.playing, isFalse);
      expect(audio.position, const Duration(seconds: 4));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(audio.playing, isTrue);
      expect(audio.position, const Duration(seconds: 4));
      expect(store.documents, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('edit, cancel, replay, restore, search, history and export', (
    tester,
  ) async {
    final store = MemoryTranscriptEditStore();
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    player.selectEpisode(episode);
    Map<String, String>? exported;
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          builder: (context, child) =>
              PlaybackLayout(controller: player, child: child!),
          home: TranscriptPage(
            episode: episode,
            editStore: store,
            loadTranscript: (_) async => editableTranscript,
            exportTranscript: (files) async {
              exported = files;
              return 'Exported test files';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> openEditor(int id) async {
      await player.seek(Duration(seconds: id == 1 ? 0 : 10));
      await tester.pumpAndSettle();
      final edit = find.byTooltip('Edit highlighted passage');
      await tester.tap(edit);
      await tester.pumpAndSettle();
    }

    final field = find.byKey(const ValueKey('transcript-editor-text'));
    await openEditor(2);
    await tester.enterText(field, 'Cancelled draft.');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.documents, isEmpty);
    await openEditor(2);
    expect(tester.widget<TextField>(field).controller!.text, 'Some fossils.');
    await tester.tap(find.text('Replay passage'));
    await tester.pumpAndSettle();
    expect(audio.position, const Duration(seconds: 10));
    expect(audio.playing, isTrue);
    await tester.tap(find.text('Pause audio'));
    await tester.pumpAndSettle();
    expect(audio.playing, isFalse);
    await tester.enterText(field, 'Corrected ammonites.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final search = find.byType(TextField);
    await tester.enterText(search, 'ammonites');
    await tester.pumpAndSettle();
    expect(find.text('1 matching passage'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear transcript search'));
    await tester.pumpAndSettle();
    await openEditor(2);
    await tester.ensureVisible(find.text('Restore original'));
    await tester.tap(find.text('Restore original'));
    expect(tester.widget<TextField>(field).controller!.text, 'Some fossils.');
    // Restore is a draft until saved; history retains the previous correction.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Correction history'));
    await tester.pumpAndSettle();
    expect(find.text('Passage 2 · 00:00:10'), findsNWidgets(2));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export reviewed transcript'));
    await tester.pumpAndSettle();
    expect(find.text('Export timing'), findsOneWidget);
    expect(exported, isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue exporting'));
    await tester.pumpAndSettle();
    expect(exported, hasLength(4));
    expect(exported!['episode-208-reviewed.txt'], contains('Some fossils.'));
    expect(
      exported!['episode-208-reviewed.json'],
      contains('Corrected ammonites.'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed save keeps the draft and empty passages are rejected', (
    tester,
  ) async {
    final store = MemoryTranscriptEditStore()..failSave = true;
    final player = PlaybackController(createEngine: FakeAudio.new);
    addTearDown(player.dispose);
    player.selectEpisode(episode);
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          builder: (context, child) =>
              PlaybackLayout(controller: player, child: child!),
          home: TranscriptPage(
            episode: episode,
            editStore: store,
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final edit = find.byTooltip('Edit highlighted passage');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('transcript-editor-text'));
    await tester.enterText(field, '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Passage text cannot be empty.'), findsOneWidget);
    await tester.enterText(field, 'A retained draft.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your draft is still here'), findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'A retained draft.',
    );
    expect(store.documents, isEmpty);
    store.failSave = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transcript-editor-text')), findsNothing);
    expect(store.documents, hasLength(1));
  });

  testWidgets(
    'conflict reload keeps the editor draft and merges latest edits',
    (tester) async {
      final store = MemoryTranscriptEditStore();
      final player = PlaybackController(createEngine: FakeAudio.new);
      addTearDown(player.dispose);
      player.selectEpisode(episode);
      await tester.pumpWidget(
        PlaybackScope(
          controller: player,
          child: MaterialApp(
            builder: (context, child) =>
                PlaybackLayout(controller: player, child: child!),
            home: TranscriptPage(
              episode: episode,
              editStore: store,
              loadTranscript: (_) async => editableTranscript,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final competing = TranscriptEdits(
        baseline: editableTranscript,
        store: store,
      );
      addTearDown(competing.dispose);
      await competing.load();

      await tester.tap(find.byTooltip('Edit highlighted passage'));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('transcript-editor-text'));
      await tester.enterText(field, 'My retained draft.');
      await competing.save(2, 'Correction from the other editor.');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Saved corrections changed in another editor. Your draft is still here; '
          'reload before saving.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Saved corrections changed in another editor. '
          'Reload before editing or exporting again.',
        ),
        findsOneWidget,
      );
      final saveButton = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(
        tester.widget<TextField>(field).controller!.text,
        'My retained draft.',
      );

      final reload = find.text('Reload saved corrections; keep draft');
      await tester.ensureVisible(reload);
      await tester.tap(reload);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field).controller!.text,
        'My retained draft.',
      );
      expect(find.textContaining('Your draft is unchanged'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final journal = jsonDecode(
        store.documents[editableTranscript.episodeGuid]!,
      ) as Map<String, dynamic>;
      final revisions = journal['revisions'] as List;
      expect(revisions, hasLength(2));
      expect(
        revisions.map((revision) => (revision as Map)['after']),
        containsAll([
          'Correction from the other editor.',
          'My retained draft.',
        ]),
      );
      expect(
        find.byKey(const ValueKey('transcript-editor-text')),
        findsNothing,
      );
    },
  );
}
