import 'dart:convert';

import 'episode_transcript.dart';

/// Apply timing only, retaining the original cue identity used by edit history.
EpisodeTranscript applyTranscriptAlignment(
  EpisodeTranscript baseline,
  String source, {
  required String audioIdentity,
  Duration? audioDuration,
}) {
  final document = jsonDecode(source);
  if (document is! Map<String, dynamic> ||
      document['schema_version'] != 1 ||
      document['episode_guid'] != baseline.episodeGuid ||
      document['audio_identity'] != audioIdentity ||
      document['audio_duration_ms'] is! int ||
      document['audio_duration_ms'] <= 0 ||
      (audioDuration != null &&
          document['audio_duration_ms'] != audioDuration.inMilliseconds) ||
      document['segments'] is! List) {
    throw const FormatException('Alignment does not match this audio edition.');
  }
  final rows = document['segments'] as List;
  if (rows.length != baseline.cues.length) {
    throw const FormatException('Alignment passage coverage is incomplete.');
  }
  final cues = <TranscriptCue>[];
  final flags = <Map<String, dynamic>>[];
  var previousEnd = 0;
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    final cue = baseline.cues[index];
    if (row is! Map<String, dynamic> ||
        row['id'] != cue.id ||
        row['baseline_text'] != cue.text ||
        row['source_start_ms'] != cue.revisionStart.inMilliseconds ||
        row['source_end_ms'] != cue.revisionEnd.inMilliseconds ||
        row['start_ms'] is! int ||
        row['end_ms'] is! int ||
        row['start_ms'] < previousEnd ||
        row['end_ms'] <= row['start_ms'] ||
        row['end_ms'] > document['audio_duration_ms'] ||
        row['review_flags'] is! List ||
        (row['review_flags'] as List).any((value) => value is! String)) {
      throw const FormatException(
        'Alignment timing or passage identity is invalid.',
      );
    }
    final timingNotes = (row['review_flags'] as List)
        .cast<String>()
        .map((flag) => 'Timing: $flag')
        .toList();
    cues.add(
      TranscriptCue(
        id: cue.id,
        start: Duration(milliseconds: row['start_ms'] as int),
        end: Duration(milliseconds: row['end_ms'] as int),
        text: cue.text,
        originalText: cue.originalText,
        reviewNotes: List.unmodifiable([...cue.reviewNotes, ...timingNotes]),
        sourceStart: cue.revisionStart,
        sourceEnd: cue.revisionEnd,
      ),
    );
    for (final note in timingNotes) {
      flags.add({
        'lines': [cue.id],
        'reason': note,
      });
    }
    previousEnd = row['end_ms'] as int;
  }
  return EpisodeTranscript(
    episodeGuid: baseline.episodeGuid,
    label: baseline.label,
    note:
        '${baseline.note} Playback uses a fixed audio edition with WhisperX '
        'passage timings. Flagged timings still need listening review.',
    cues: List.unmodifiable(cues),
    audioIdentity: audioIdentity,
    sourceDocument: {
      ...?baseline.sourceDocument,
      'audio_identity': audioIdentity,
      'alignment': document,
      'unresolved': [
        ...?baseline.sourceDocument?['unresolved'] as List?,
        ...flags,
      ],
    },
  );
}
