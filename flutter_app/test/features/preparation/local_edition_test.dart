import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/data/episode_audio.dart';
import 'package:common_descent_listing/data/bundled_transcripts.dart';
import 'package:common_descent_listing/data/local_prepared_episodes.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/services/file_transcript_edits.dart';

class EditionAudio extends AudioEngine {
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration = const Duration(hours: 2);
  @override
  bool playing = false;
  @override
  bool get buffering => false;
  @override
  bool get completed => false;
  @override
  String? get error => null;
  Uri? uri;
  @override
  Future<void> load(Uri source, Duration start) async {
    uri = source;
    position = start;
  }

  @override
  void play() {
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> seek(Duration target) async {
    position = target;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }
}

void main() {
  tearDown(() => LocalPreparedEpisodes.replace([]));
  test('runtime audio and transcript use the same edition; invalid timing identity fails', () async {
    final audio = Uri.parse(
      'http://127.0.0.1:8765/media/key/edition/audio.opus',
    );
    final episode = Episode(
      guid: 'guid',
      title: 'Sample',
      number: '1',
      segments: const [],
    );
    Map<String, dynamic> timing = {
      'schema_version': 1,
      'episode_guid': 'guid',
      'audio_identity': 'sha256:local',
      'audio_duration_ms': 5000,
      'segments': [
        {
          'id': 1,
          'baseline_text': 'Sample',
          'source_start_ms': 0,
          'source_end_ms': 1000,
          'start_ms': 50,
          'end_ms': 1050,
          'review_flags': [],
        },
      ],
    };
    LocalPreparedEpisodes.replace([
      LocalPreparedEdition(
        guid: 'guid',
        edition: 'a' * 32,
        audioUri: audio,
        audioIdentity: 'sha256:local',
        duration: const Duration(seconds: 5),
        passageCount: 1,
        loadText: (file) async => jsonEncode(
          file.endsWith('alignment.json')
              ? timing
              : {
                  'schema_version': 1,
                  'episode_guid': 'guid',
                  'changes': [],
                  'unresolved': [],
                  'review': {
                    'label': 'Machine transcribed; not reviewed.',
                    'note': 'Fixture',
                  },
                  'segments': [
                    {'id': 1, 'start_ms': 0, 'end_ms': 1000, 'text': 'Sample'},
                  ],
                },
        ),
      ),
    ]);
    expect(EpisodeAudio.sourceFor(episode), audio);
    expect(BundledTranscripts.hasEpisode('guid'), isTrue);
    expect(
      (await BundledTranscripts.load('guid')).cues.single.start.inMilliseconds,
      50,
    );
    timing = {...timing, 'audio_identity': 'sha256:different'};
    await expectLater(BundledTranscripts.load('guid'), throwsFormatException);
  });
  test(
    'editor bookmark cannot resume old timestamps in a replacement recording',
    () async {
      final episode = Episode(
        guid: 'guid',
        title: 'Sample',
        number: '1',
        segments: const [],
      );
      LocalPreparedEdition edition(String id) => LocalPreparedEdition(
        guid: 'guid',
        edition: id,
        audioUri: Uri.parse('http://127.0.0.1:8765/$id/audio.opus'),
        audioIdentity: 'sha256:$id',
        duration: const Duration(hours: 2),
        passageCount: 1,
        loadText: (_) async => '{}',
      );
      final engine = EditionAudio();
      final player = PlaybackController(createEngine: () => engine);
      LocalPreparedEpisodes.replace([edition('old')]);
      await player.playEpisode(episode, from: const Duration(minutes: 10));
      final bookmark = await player.pauseForEditing();
      LocalPreparedEpisodes.replace([edition('new')]);
      await player.refreshPreparedEdition();
      await player.restoreAfterEditing(bookmark!);
      expect(player.playing, isFalse);
      expect(player.position, Duration.zero);
      await player.playEpisode(episode);
      expect(engine.uri, Uri.parse('http://127.0.0.1:8765/new/audio.opus'));
      expect(player.position, Duration.zero);
      player.dispose();
    },
  );

  test(
    'new transcript edition does not overwrite an existing correction journal',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'transcript-editions',
      );
      try {
        final old = FileTranscriptEditStore(directory: () async => directory);
        final next = FileTranscriptEditStore(
          directory: () async => directory,
          editionKey: 'b' * 32,
        );
        expect(
          await old.writeIfUnchanged(
            'guid',
            expectedDocument: null,
            document: 'old corrections',
          ),
          isTrue,
        );
        expect(await next.read('guid'), isNull);
        expect(
          await next.writeIfUnchanged(
            'guid',
            expectedDocument: null,
            document: 'new corrections',
          ),
          isTrue,
        );
        expect(await old.read('guid'), 'old corrections');
        expect(await next.read('guid'), 'new corrections');
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
