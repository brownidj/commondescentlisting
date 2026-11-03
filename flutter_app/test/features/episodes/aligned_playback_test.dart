import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/bundled_episode_packages.dart';
import 'package:common_descent_listing/data/bundled_transcripts.dart';
import 'package:common_descent_listing/data/episode_audio.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/models/transcript_alignment.dart';
import 'package:common_descent_listing/services/playback_controller.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';
import 'package:common_descent_listing/services/transcript_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'playback_controller_test.dart' show FakeAudio, episode;
import 'transcript_edit_test_support.dart';

void main() {
  String alignmentSource() =>
      File(BundledEpisodePackages.karooAlignmentAsset).readAsStringSync();
  EpisodeTranscript original() => EpisodeTranscript.parse(
    File(BundledEpisodePackages.karooReviewedAsset).readAsStringSync(),
    episodeGuid: BundledTranscripts.episode208Guid,
  );
  EpisodeTranscript aligned() => applyTranscriptAlignment(
    original(),
    alignmentSource(),
    audioIdentity: EpisodeAudio.karooIdentity,
  );

  test(
    'full alignment preserves all IDs/text and original edit references',
    () {
      final old = original();
      final current = aligned();
      expect(current.cues.length, 1032);
      expect(current.audioIdentity, EpisodeAudio.karooIdentity);
      expect(current.cues.first.end, lessThan(const Duration(seconds: 5)));
      for (var i = 0; i < old.cues.length; i++) {
        expect(current.cues[i].id, old.cues[i].id);
        expect(current.cues[i].text, old.cues[i].text);
        expect(current.cues[i].originalText, old.cues[i].originalText);
        expect(current.cues[i].revisionStart, old.cues[i].start);
        expect(current.cues[i].revisionEnd, old.cues[i].end);
        expect(current.cueAt(current.cues[i].start)?.id, old.cues[i].id);
        if (i > 0) {
          expect(
            current.cues[i].start,
            greaterThanOrEqualTo(current.cues[i - 1].end),
          );
        }
      }
      expect(File(EpisodeAudio.karooAsset).lengthSync(), greaterThan(0));
    },
  );

  test('wrong edition, missing cues and overlapping timings are rejected', () {
    final document = jsonDecode(alignmentSource()) as Map<String, dynamic>;
    String altered(void Function(Map<String, dynamic>) change) {
      final copy = jsonDecode(jsonEncode(document)) as Map<String, dynamic>;
      change(copy);
      return jsonEncode(copy);
    }

    for (final invalid in [
      altered((d) => d['audio_identity'] = 'different-audio'),
      altered((d) => (d['segments'] as List).removeLast()),
      altered((d) => d['segments'][1]['start_ms'] = 0),
      altered((d) => d['segments'][0]['baseline_text'] = 'Unrelated text'),
    ]) {
      expect(
        () => applyTranscriptAlignment(
          original(),
          invalid,
          audioIdentity: EpisodeAudio.karooIdentity,
        ),
        throwsFormatException,
      );
    }
  });

  test('legacy edits survive new timings; old advert offset is isolated from saved nudges', () async {
    final store = MemoryTranscriptEditStore();
    final old = TranscriptEdits(baseline: original(), store: store);
    addTearDown(old.dispose);
    await old.load();
    await old.save(2, 'Hello William.');
    await old.setSyncOffset(const Duration(milliseconds: -30501));
    final fixed = TranscriptEdits(baseline: aligned(), store: store);
    addTearDown(fixed.dispose);
    await fixed.load();
    expect(fixed.ready, isTrue);
    expect(fixed.syncOffset, Duration.zero);
    expect(fixed.current.cues[1].text, 'Hello William.');
    expect(fixed.history, hasLength(1));
    await fixed.setSyncOffset(const Duration(milliseconds: 500));
    await fixed.save(3, 'Hello Dave.');
    final reopened = TranscriptEdits(baseline: aligned(), store: store);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.ready, isTrue);
    expect(reopened.syncOffset, const Duration(milliseconds: 500));
    expect(reopened.history, hasLength(2));
    await old.load();
    expect(old.ready, isTrue);
    expect(old.syncOffset, const Duration(milliseconds: -30501));
    expect(old.current.cues[2].text, 'Hello Dave.');
    final document = jsonDecode(
      transcriptExportFiles(reopened, 'aligned')['aligned.json']!,
    );
    final exported = EpisodeTranscript.parse(
      jsonEncode(document),
      episodeGuid: old.baseline.episodeGuid,
    );
    expect(exported.audioIdentity, EpisodeAudio.karooIdentity);
    expect(exported.cues[1].start, reopened.current.cues[1].start);
    expect(exported.cues[1].revisionStart, old.baseline.cues[1].start);
    expect(exported.cues[1].text, 'Hello William.');
  });

  test(
    'MP3 calibration and edits survive the move to a distinct Opus edition',
    () async {
      final store = MemoryTranscriptEditStore();
      final previous = TranscriptEdits(
        baseline: applyTranscriptAlignment(
          original(),
          File('assets/transcripts/episode-208-karoo-alignment.json')
              .readAsStringSync(),
          audioIdentity: 'sha256:${BundledEpisodePackages.karooSourceSha256}',
        ),
        store: store,
      );
      addTearDown(previous.dispose);
      await previous.load();
      await previous.save(2, 'Hello William.');
      await previous.setSyncOffset(const Duration(milliseconds: 1500));
      final opus = TranscriptEdits(baseline: aligned(), store: store);
      addTearDown(opus.dispose);
      await opus.load();
      expect(opus.ready, isTrue);
      expect(opus.current.cues[1].text, 'Hello William.');
      expect(opus.history, hasLength(1));
      expect(opus.syncOffset, Duration.zero);
      await opus.setSyncOffset(const Duration(milliseconds: -500));
      await previous.load();
      expect(previous.syncOffset, const Duration(milliseconds: 1500));
      await opus.load();
      expect(opus.syncOffset, const Duration(milliseconds: -500));
    },
  );

  test(
    'play, seek and editor restoration use the fixed Opus edition',
    () async {
      final audio = FakeAudio();
      final player = PlaybackController(createEngine: () => audio);
      addTearDown(player.dispose);
      final transcript = aligned();
      final selected = episode(
        EpisodeAudio.karooGuid,
        url: 'https://example.com/changeable-adverts.mp3',
      );
      player.setTranscriptContext(transcript, Duration.zero);
      final cue = transcript.cues[440];
      await player.playEpisode(selected, from: cue.start);
      expect(audio.source?.scheme, 'asset');
      expect(audio.source?.path, '/${EpisodeAudio.karooAsset}');
      expect(player.currentPassage?.id, cue.id);
      final bookmark = (await player.pauseForEditing())!;
      await player.playEpisode(
        episode('other', url: 'https://example.com/other.mp3'),
      );
      await player.restoreAfterEditing(bookmark);
      expect(audio.source?.scheme, 'asset');
      expect(player.position, cue.start);
      expect(player.playing, isTrue);
    },
  );
}
