import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/bundled_transcripts.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final asset = File('assets/transcripts/episode-208-karoo-reviewed.json');

  test('reviewed asset retains baseline timing and uncertain wording', () {
    final source = asset.readAsStringSync();
    final transcript = EpisodeTranscript.parse(
      source,
      episodeGuid: BundledTranscripts.episode208Guid,
    );
    final baseline = jsonDecode(
      File('../outputs/whisper-test/episode-208-karoo.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final originalCues = baseline['transcription'] as List;
    expect(transcript.cues, hasLength(originalCues.length));
    for (var i = 0; i < transcript.cues.length; i++) {
      final original = originalCues[i] as Map<String, dynamic>;
      final offsets = original['offsets'] as Map<String, dynamic>;
      expect(transcript.cues[i].start.inMilliseconds, offsets['from']);
      expect(transcript.cues[i].end.inMilliseconds, offsets['to']);
      expect(
        transcript.cues[i].originalText,
        (original['text'] as String).trim(),
      );
    }
    expect(transcript.cues.first.text, contains('Common Descent'));
    expect(transcript.cues[100].text, contains('Caenorhabditis elegans'));
    expect(transcript.cues[927].text, contains('drassic'));
    expect(transcript.cues[927].reviewNotes, isNotEmpty);
    expect(transcript.cues[684].text, contains('dicynodon not a mammal'));
    expect(transcript.cues[971].text, contains('alleys episodes'));
    expect(BundledTranscripts.hasEpisode('another-episode'), isFalse);
  });

  test('mismatched identity and invalid timing are rejected', () {
    final source = asset.readAsStringSync();
    expect(
      () => EpisodeTranscript.parse(source, episodeGuid: 'wrong'),
      throwsFormatException,
    );
    final decoded = jsonDecode(source) as Map<String, dynamic>;
    final cues = decoded['segments'] as List;
    (cues[1] as Map<String, dynamic>)['start_ms'] = -1;
    expect(
      () => EpisodeTranscript.parse(
        jsonEncode(decoded),
        episodeGuid: BundledTranscripts.episode208Guid,
      ),
      throwsFormatException,
    );
  });

  test('review references must be unique and point to existing cues', () {
    final source = asset.readAsStringSync();
    EpisodeTranscript parse(Map<String, dynamic> document) =>
        EpisodeTranscript.parse(
          jsonEncode(document),
          episodeGuid: BundledTranscripts.episode208Guid,
        );

    final duplicateChange = jsonDecode(source) as Map<String, dynamic>;
    final changes = duplicateChange['changes'] as List;
    changes.add(Map<String, dynamic>.from(changes.first as Map));
    expect(() => parse(duplicateChange), throwsFormatException);

    final missingChange = jsonDecode(source) as Map<String, dynamic>;
    final missingChanges = missingChange['changes'] as List;
    (missingChanges.first as Map<String, dynamic>)['line'] = -1;
    expect(() => parse(missingChange), throwsFormatException);

    final duplicateFlagLine = jsonDecode(source) as Map<String, dynamic>;
    final duplicateFlags = duplicateFlagLine['unresolved'] as List;
    final firstFlag = Map<String, dynamic>.from(duplicateFlags.first as Map);
    final firstLines = List<dynamic>.from(firstFlag['lines'] as List);
    firstFlag['lines'] = [...firstLines, firstLines.first];
    duplicateFlags[0] = firstFlag;
    expect(() => parse(duplicateFlagLine), throwsFormatException);

    final missingFlagLine = jsonDecode(source) as Map<String, dynamic>;
    final missingFlags = missingFlagLine['unresolved'] as List;
    (missingFlags.first as Map<String, dynamic>)['lines'] = [-1];
    expect(() => parse(missingFlagLine), throwsFormatException);

    final distinctFlags = jsonDecode(source) as Map<String, dynamic>;
    final flags = distinctFlags['unresolved'] as List;
    final originalFlag = Map<String, dynamic>.from(flags.first as Map);
    flags.add({...originalFlag, 'reason': 'A separate review reason.'});
    final transcript = parse(distinctFlags);
    final firstLine = (originalFlag['lines'] as List).first as int;
    final flaggedCue = transcript.cues.firstWhere(
      (cue) => cue.id == firstLine,
    );
    expect(flaggedCue.reviewNotes, contains(originalFlag['reason']));
    expect(flaggedCue.reviewNotes, contains('A separate review reason.'));
  });
}
