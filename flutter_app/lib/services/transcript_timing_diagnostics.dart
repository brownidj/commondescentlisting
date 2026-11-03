import 'dart:convert';

import '../models/episode_transcript.dart';

/// Observations only: these never modify transcript timestamps or calibration.
class TranscriptTimingSample {
  TranscriptTimingSample({
    required this.cue,
    required this.audioPosition,
    required this.offset,
    required this.highlightedId,
    required this.audioDuration,
    required this.recordedAt,
  });

  final TranscriptCue cue;
  final Duration audioPosition;
  final Duration offset;
  final int? highlightedId;
  final Duration? audioDuration;
  final DateTime recordedAt;

  /// Positive means the words start later in the audio than the stored time.
  Duration get rawDifference => audioPosition - cue.start;
  Duration get residual => audioPosition + offset - cue.start;

  Map<String, Object?> toJson() => {
    'recorded_at_utc': recordedAt.toUtc().toIso8601String(),
    'passage_id': cue.id,
    'passage_text': cue.text,
    'stored_start_ms': cue.start.inMilliseconds,
    'stored_end_ms': cue.end.inMilliseconds,
    'observed_audio_start_ms': audioPosition.inMilliseconds,
    'saved_offset_ms': offset.inMilliseconds,
    'adjusted_clock_ms': (audioPosition + offset).inMilliseconds,
    'raw_difference_ms': rawDifference.inMilliseconds,
    'calibrated_residual_ms': residual.inMilliseconds,
    'highlighted_passage_id': highlightedId,
    'audio_duration_ms': audioDuration?.inMilliseconds,
    'playing': true,
    'buffering': false,
  };
}

class TranscriptTimingDiagnostics {
  TranscriptTimingDiagnostics(this.episodeGuid, {this.audioIdentity});
  final String episodeGuid;
  final String? audioIdentity;
  final samples = <TranscriptTimingSample>[];

  String report(String title) => const JsonEncoder.withIndent('  ').convert({
    'schema_version': 1,
    'episode_guid': episodeGuid,
    'audio_identity': audioIdentity,
    'episode_title': title,
    'method':
        'Human marks first spoken words; not automatic audio recognition.',
    'raw_difference':
        'observed audio start minus stored transcript start; '
        'positive means words occur later in the audio.',
    'calibrated_residual':
        'audio start plus saved offset minus stored start; '
        'zero means the current adjustment aligns this observation.',
    'samples': samples.map((sample) => sample.toJson()).toList(),
  });
}

String diagnosticTime(Duration value, {bool signed = false}) {
  final ms = value.inMilliseconds.abs();
  final sign = value.isNegative ? '-' : (signed ? '+' : '');
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  return '$sign${pad(ms ~/ 3600000, 2)}:${pad(ms ~/ 60000 % 60, 2)}:'
      '${pad(ms ~/ 1000 % 60, 2)}.${pad(ms % 1000, 3)}';
}
