import 'dart:io';

import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/playback_preferences.dart';
import 'package:common_descent_listing/widgets/playback_settings_dialog.dart';
import 'package:common_descent_listing/widgets/playback_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio, episode;

class MemoryPreferences implements PlaybackPreferenceStore {
  PlaybackOutput? saved;
  bool fail = false;
  @override
  Future<PlaybackOutput?> read() async => saved;
  @override
  Future<void> save(PlaybackOutput output) async {
    if (fail) throw StateError('Write failed');
    saved = output;
  }
}

void main() {
  test(
    'preference survives a new store instance; invalid data is rejected',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'playback-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FilePlaybackPreferenceStore(
        directory: () async => directory,
      );
      expect(await store.read(), isNull);
      await store.save(PlaybackOutput.applePodcasts);
      final reopened = FilePlaybackPreferenceStore(
        directory: () async => directory,
      );
      expect(await reopened.read(), PlaybackOutput.applePodcasts);
      await File('${directory.path}/settings/playback.json')
          .writeAsString('invalid');
      await expectLater(reopened.read(), throwsFormatException);
    },
  );

  test(
    'failed preference save retains the selected episode and resume position',
    () async {
      final store = MemoryPreferences();
      final audio = FakeAudio();
      final player = PlaybackController(
        createEngine: () => audio,
        preferenceStore: store,
      );
      addTearDown(player.dispose);
      await player.initialisePreferences();
      await player.playEpisode(
        episode('plants', url: 'https://example.com/plants.mp3'),
        from: const Duration(seconds: 23),
      );
      expect(audio.playing, isTrue);
      store.fail = true;
      await player.setOutput(PlaybackOutput.applePodcasts);
      expect(player.output, PlaybackOutput.audioPlayer);
      expect(player.episode?.guid, 'plants');
      expect(audio.playing, isFalse);
      expect(player.position, const Duration(seconds: 23));
      expect(player.preferencesError, isNotNull);

      store.fail = false;
      await player.toggle();
      expect(audio.playing, isTrue);
      expect(audio.position, const Duration(seconds: 23));
      await player.setOutput(PlaybackOutput.applePodcasts);
      expect(audio.playing, isFalse);
      expect(player.output, PlaybackOutput.applePodcasts);
      expect(store.saved, PlaybackOutput.applePodcasts);
      store.fail = true;
      await player.setOutput(PlaybackOutput.audioPlayer);
      expect(player.output, PlaybackOutput.applePodcasts);
      expect(player.preferencesError, isNotNull);
      final reopened = PlaybackController(
        createEngine: () => FakeAudio(),
        preferenceStore: store,
      );
      addTearDown(reopened.dispose);
      await reopened.initialisePreferences();
      expect(reopened.output, PlaybackOutput.applePodcasts);
    },
  );

  testWidgets('settings lets a listener choose either player', (tester) async {
    final store = MemoryPreferences();
    final player = PlaybackController(
      createEngine: () => FakeAudio(),
      preferenceStore: store,
    );
    addTearDown(player.dispose);
    await player.initialisePreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlaybackSettingsDialog(controller: player)),
        builder: (context, child) => ListenableBuilder(
          listenable: player,
          builder: (context, _) => PlaybackLayout(
            controller: player,
            showPlayer: player.output == PlaybackOutput.audioPlayer,
            child: child!,
          ),
        ),
      ),
    );
    expect(find.byType(PlaybackBar), findsOneWidget);
    await tester.tap(find.text('Apple Podcasts'));
    await tester.pumpAndSettle();
    expect(player.output, PlaybackOutput.applePodcasts);
    expect(find.byType(PlaybackBar), findsNothing);
    await tester.tap(find.text('Audio player'));
    await tester.pumpAndSettle();
    expect(player.output, PlaybackOutput.audioPlayer);
    expect(find.byType(PlaybackBar), findsOneWidget);
  });
}
