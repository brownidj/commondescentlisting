import 'dart:async';

import 'package:common_descent_listing/features/episodes/transcript_page.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:common_descent_listing/widgets/playback_route_observer.dart';
import 'package:common_descent_listing/widgets/playback_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio;
import 'transcript_edit_test_support.dart';

void main() {
  final selected = Episode(
    guid: editableTranscript.episodeGuid,
    title: 'Episode',
    number: '208',
    segments: [
      for (var i = 0; i < 2; i++)
        Segment(
          sourceIndex: i,
          guid: editableTranscript.episodeGuid,
          episodeTitle: 'Episode',
          type: 'Main Discussion',
          title: i == 0 ? 'First' : 'Second',
          startTime: Duration(seconds: i * 10),
          audioUrl: 'https://example.com/audio.mp3',
        ),
    ],
  );

  Future<void> mount(WidgetTester tester, PlaybackController player) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          navigatorObservers: [playbackRouteObserver],
          builder: (context, child) =>
              PlaybackLayout(controller: player, child: child!),
          home: TranscriptPage(
            episode: selected,
            editStore: MemoryTranscriptEditStore(),
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Space pauses/resumes, but does not steal typing from search or editor',
    (tester) async {
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      player.selectEpisode(selected);
      await mount(tester, player);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(audio.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
      final search = find.byType(TextField);
      await tester.tap(search);
      await tester.enterText(search, 'Karoo rocks');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
      await tester.tap(find.byTooltip('Clear transcript search'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit highlighted passage'));
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('transcript-editor-text'));
      await tester.ensureVisible(editor);
      await tester.tap(editor);
      await tester.pumpAndSettle();
      final editorInput = tester.widget<EditableText>(
        find.descendant(of: editor, matching: find.byType(EditableText)),
      );
      expect(editorInput.focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(audio.playing, isFalse);
      expect(find.text('Edit passage 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Space belongs to focused controls and modal routes', (
    tester,
  ) async {
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    await player.playEpisode(selected);
    await player.toggle();
    final controlFocus = FocusNode();
    addTearDown(controlFocus.dispose);
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            PlaybackLayout(controller: player, child: child!),
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                focusNode: controlFocus,
                onPressed: () => activations++,
                child: const Text('Focused control'),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      content: Text('Modal route is open'),
                    ),
                  ),
                  child: const Text('Open modal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controlFocus.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(activations, 1);
    expect(audio.playing, isFalse);

    await tester.tap(find.text('Open modal'));
    await tester.pumpAndSettle();
    expect(find.text('Modal route is open'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(audio.playing, isFalse);
    expect(find.text('Modal route is open'), findsOneWidget);
  });

  testWidgets(
    'secondary click selects for Edit; primary click and chapters start audio',
    (tester) async {
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      await player.playEpisode(selected, from: const Duration(seconds: 4));
      await mount(tester, player);
      final second = find.byKey(const ValueKey('transcript-cue-2'));
      await tester.ensureVisible(second);
      await tester.tap(second, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(seconds: 4));
      expect(audio.playing, isTrue);
      expect(tester.widget<ListTile>(second).selected, isTrue);
      final first = find.byKey(const ValueKey('transcript-cue-1'));
      final playingTile = tester.widget<ListTile>(first);
      final editingTile = tester.widget<ListTile>(second);
      expect(playingTile.selected, isTrue);
      expect(
        editingTile.selectedTileColor,
        isNot(playingTile.selectedTileColor),
      );
      expect(editingTile.shape, isA<RoundedRectangleBorder>());
      expect(find.text('Audio position'), findsOneWidget);
      expect(find.text('Passage 2 selected for editing'), findsOneWidget);
      expect(find.text('Passage 1 of 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit highlighted passage'));
      await tester.pumpAndSettle();
      expect(find.text('Edit passage 2'), findsOneWidget);
      expect(audio.playing, isFalse);
      expect(audio.position, const Duration(seconds: 4));
      await tester.tap(find.text('Replay passage'));
      await tester.pumpAndSettle();
      expect(audio.playing, isTrue);
      expect(audio.position, const Duration(seconds: 10));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(audio.playing, isTrue);
      expect(audio.position, const Duration(seconds: 4));
      await player.toggle();
      await tester.pumpAndSettle();
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(seconds: 10));
      expect(audio.playing, isTrue);
      expect(find.text('Passage 2 of 2'), findsOneWidget);
      expect(find.text('Passage 2 selected for editing'), findsNothing);
      await player.toggle();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pumpAndSettle();
      expect(audio.position, Duration.zero);
      expect(audio.playing, isTrue);
      expect(find.text('Passage 1 of 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Save returns an audition to its paused listening position', (
    tester,
  ) async {
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    await player.playEpisode(selected, from: const Duration(seconds: 4));
    await player.toggle();
    await mount(tester, player);
    await tester.tap(
      find.byKey(const ValueKey('transcript-cue-2')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit highlighted passage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay passage'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transcript-editor-text')),
      'Some corrected fossils.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit passage 2'), findsNothing);
    expect(find.text('Some corrected fossils.'), findsOneWidget);
    expect(player.position, const Duration(seconds: 4));
    expect(player.playing, isFalse);
  });

  test('editing restores paused previews without loading audio', () async {
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    player.selectEpisode(selected);
    await player.seek(const Duration(seconds: 4));
    final bookmark = (await player.pauseForEditing())!;
    await player.restoreAfterEditing(bookmark);
    expect(audio.loads, 0);
    expect(player.position, const Duration(seconds: 4));
    await player.playEpisode(selected, from: const Duration(seconds: 10));
    await player.restoreAfterEditing(bookmark);
    expect(player.position, const Duration(seconds: 4));
    expect(player.playing, isFalse);
  });

  test('closing Edit waits for a pending Replay before restoring', () async {
    final audio = FakeAudio();
    final player = PlaybackController(createEngine: () => audio);
    addTearDown(player.dispose);
    player.selectEpisode(selected);
    await player.seek(const Duration(seconds: 4));
    final bookmark = (await player.pauseForEditing())!;
    audio.pending = Completer<void>();
    final replay = player.playEpisode(
      selected,
      from: const Duration(seconds: 10),
    );
    final restore = player.restoreAfterEditing(bookmark);
    audio.pending!.complete();
    await replay;
    await restore;
    expect(player.position, const Duration(seconds: 4));
    expect(player.playing, isFalse);
  });

  testWidgets('only the current transcript route owns the edit action', (
    tester,
  ) async {
    final player = PlaybackController(createEngine: FakeAudio.new);
    addTearDown(player.dispose);
    await player.playEpisode(selected);
    final otherEpisode = Episode(
      guid: 'other-transcript-route',
      title: 'Other episode',
      number: '209',
      segments: [],
    );
    final otherTranscript = EpisodeTranscript(
      episodeGuid: otherEpisode.guid,
      label: 'Other transcript',
      note: '',
      cues: editableTranscript.cues,
    );
    await tester.pumpWidget(
      PlaybackScope(
        controller: player,
        child: MaterialApp(
          navigatorObservers: [playbackRouteObserver],
          builder: (context, child) =>
              PlaybackLayout(controller: player, child: child!),
          home: TranscriptPage(
            episode: selected,
            editStore: MemoryTranscriptEditStore(),
            loadTranscript: (_) async => editableTranscript,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => TranscriptPage(
            episode: otherEpisode,
            editStore: MemoryTranscriptEditStore(),
            loadTranscript: (_) async => otherTranscript,
          ),
        ),
      ).then<void>((_) {}),
    );
    await tester.pumpAndSettle();
    expect(player.transcriptEditAction?.guid, otherEpisode.guid);
    final editButton = find.byKey(const ValueKey('player-transcript-edit'));
    expect(tester.widget<IconButton>(editButton).onPressed, isNull);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(player.transcriptEditAction?.guid, selected.guid);
    expect(tester.widget<IconButton>(editButton).onPressed, isNotNull);
    await tester.tap(editButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transcript-editor-text')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'passage context follows calibration and does not leak to another episode',
    () async {
      final player = PlaybackController(createEngine: FakeAudio.new);
      addTearDown(player.dispose);
      player.setTranscriptContext(
        editableTranscript,
        const Duration(seconds: 6),
      );
      player.selectEpisode(selected);
      await player.seek(const Duration(seconds: 4));
      expect(player.currentPassage?.id, 2);
      expect(player.transcriptPassageCount, 2);
      await player.close();
      player.selectEpisode(
        Episode(
          guid: 'other',
          title: 'Other',
          number: null,
          segments: const [],
        ),
      );
      expect(player.currentPassage, isNull);
      expect(player.transcriptPassageCount, isNull);
    },
  );
}
