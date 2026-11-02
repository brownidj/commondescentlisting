import 'dart:async';

import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

Episode episode(String guid, {String? url}) => Episode(
  guid: guid,
  title: guid,
  number: null,
  segments: [
    Segment(
      sourceIndex: 0,
      guid: guid,
      episodeTitle: guid,
      type: 'Episode',
      audioUrl: url,
    ),
  ],
);

class FakeAudio extends AudioEngine {
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration = const Duration(hours: 2);
  @override
  bool playing = false;
  @override
  bool buffering = false;
  @override
  bool completed = false;
  @override
  String? error;
  int loads = 0;
  Uri? source;
  bool fail = false;
  bool failPause = false;
  bool failSeek = false;
  bool failStop = false;
  bool released = false;
  Completer<void>? pending;

  @override
  Future<void> load(Uri uri, Duration position) async {
    loads++;
    if (fail) throw StateError('offline');
    if (pending != null) await pending!.future;
    source = uri;
    this.position = position;
  }

  @override
  void play() {
    playing = true;
  }

  @override
  Future<void> pause() async {
    if (failPause) throw StateError('Pause failed');
    playing = false;
  }

  @override
  Future<void> seek(Duration value) async {
    if (failSeek) throw StateError('Seek failed');
    position = value;
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('Stop failed');
    playing = false;
    position = Duration.zero;
  }

  @override
  void dispose() {
    released = true;
    super.dispose();
  }
}

void main() {
  late FakeAudio audio;
  late PlaybackController player;
  final first = episode('first', url: 'https://example.com/one.mp3');
  setUp(() {
    audio = FakeAudio();
    player = PlaybackController(createEngine: () => audio);
  });
  tearDown(() => player.dispose());

  test('preview is silent, retains a selected time, and does not interrupt playback', () async {
    player.selectEpisode(first);
    expect(player.episode, first);
    expect(audio.loads, 0);
    await player.seek(const Duration(minutes: 5));
    expect(player.position.inMinutes, 5);
    expect(audio.loads, 0);
    await player.toggle();
    expect(audio.position.inMinutes, 5);
    final other = episode('other', url: 'https://example.com/other.mp3');
    player.selectEpisode(other);
    expect(player.episode, first);
    await player.toggle();
    player.selectEpisode(other);
    expect(player.episode, first);
  });

  test(
    'load at requested time; same episode seeks without reloading',
    () async {
      await player.playEpisode(
        first,
        from: const Duration(minutes: 47, seconds: 35),
      );
      expect(audio.position.inSeconds, 2855);
      expect(audio.playing, isTrue);
      await player.playEpisode(
        first,
        from: const Duration(minutes: 5, seconds: 25),
      );
      expect(audio.position.inSeconds, 325);
      expect(audio.loads, 1);
      await player.toggle();
      expect(audio.playing, isFalse);
      await player.toggle();
      expect(audio.position.inSeconds, 325);
      expect(audio.playing, isTrue);
      await player.playEpisode(first, from: Duration.zero);
      expect(audio.position, Duration.zero);
    },
  );

  test('failed pause and seek preserve the active engine state', () async {
    await player.playEpisode(first, from: const Duration(seconds: 20));
    audio.failPause = true;
    await player.toggle();
    expect(player.episode, first);
    expect(player.playing, isTrue);
    expect(player.duration, audio.duration);
    expect(player.error, isNotNull);

    audio.failPause = false;
    audio.failSeek = true;
    await player.seek(const Duration(seconds: 40));
    expect(player.episode, first);
    expect(player.playing, isTrue);
    expect(player.position, const Duration(seconds: 20));
    expect(player.duration, audio.duration);
    expect(player.error, isNotNull);

    audio.failSeek = false;
    await player.toggle();
    expect(player.playing, isFalse);
    expect(player.error, isNull);
  });

  test('failed pause keeps the previous episode selected during a switch', () async {
    await player.playEpisode(first, from: const Duration(seconds: 25));
    final second = episode('second', url: 'https://example.com/two.mp3');
    audio.failPause = true;
    await player.playEpisode(second);
    expect(player.episode, first);
    expect(player.playing, isTrue);
    expect(player.position, const Duration(seconds: 25));

    audio.failPause = false;
    await player.playEpisode(second);
    expect(player.episode, second);
    expect(player.playing, isTrue);
    expect(audio.source, second.audioUri);
  });

  test('failed stop does not hide audio that is still playing', () async {
    await player.playEpisode(first);
    audio.failStop = true;
    await player.close();
    expect(player.episode, first);
    expect(player.playing, isTrue);
    expect(player.duration, audio.duration);
    expect(player.error, isNotNull);
  });

  test(
    'editor replay restores a different playing episode and position',
    () async {
      await player.playEpisode(first, from: const Duration(seconds: 25));
      final bookmark = await player.pauseForEditing();
      expect(bookmark, isNotNull);
      expect(audio.playing, isFalse);

      final second = episode('second', url: 'https://example.com/two.mp3');
      await player.playEpisode(second, from: const Duration(seconds: 10));
      expect(player.episode, second);
      expect(audio.playing, isTrue);

      await player.restoreAfterEditing(bookmark!);
      expect(player.episode, first);
      expect(audio.source, first.audioUri);
      expect(player.position, const Duration(seconds: 25));
      expect(player.playing, isTrue);
    },
  );

  test('editor replay restores an initially empty player preview', () async {
    final bookmark = await player.pauseForEditing();
    expect(bookmark, isNotNull);
    await player.playEpisode(first, from: const Duration(seconds: 10));
    expect(player.playing, isTrue);

    await player.restoreAfterEditing(bookmark!);
    expect(player.episode, isNull);
    expect(player.playing, isFalse);
    expect(player.duration, isNull);
  });

  test(
    'switching episode changes source and does not reuse old position',
    () async {
      await player.playEpisode(first, from: const Duration(hours: 1));
      final second = episode('second', url: 'https://example.com/two.mp3');
      await player.playEpisode(second);
      expect(audio.source, second.audioUri);
      expect(audio.position, Duration.zero);
      expect(audio.loads, 2);
      await player.close();
      expect(player.episode, isNull);
      expect(audio.playing, isFalse);
    },
  );

  test('skip bounds, completion replay and recoverable load failure', () async {
    audio.fail = true;
    await player.playEpisode(first);
    expect(player.error, isNotNull);
    expect(player.busy, isFalse);
    audio.fail = false;
    await player.playEpisode(first);
    expect(player.error, isNull);
    await player.skip(const Duration(seconds: -15));
    expect(audio.position, Duration.zero);
    await player.seek(const Duration(hours: 3));
    expect(audio.position, audio.duration);
    audio.completed = true;
    audio.playing = false;
    await player.toggle();
    expect(audio.position, Duration.zero);
  });

  test('missing or unsafe audio does not initialise native playback', () async {
    for (final url in [
      null,
      'http://example.com/audio.mp3',
      'file:///secret',
      'https://user:pass@example.com/audio.mp3',
    ]) {
      await player.playEpisode(episode('missing', url: url));
      expect(player.error, isNotNull);
      expect(audio.loads, 0);
    }
  });

  test('a pending load prevents competing source changes', () async {
    audio.pending = Completer<void>();
    final loading = player.playEpisode(first);
    await Future<void>.delayed(Duration.zero);
    expect(player.busy, isTrue);
    await player.playEpisode(
      episode('second', url: 'https://example.com/two.mp3'),
    );
    audio.pending!.complete();
    await loading;
    expect(player.episode?.guid, 'first');
    expect(audio.loads, 1);
  });
}
