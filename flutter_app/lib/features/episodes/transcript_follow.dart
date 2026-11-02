import '../../models/episode_transcript.dart';

/// Finds a passage using its original timing; gaps and the exact final end have
/// no active passage. Transcript cues are validated as ordered/non-overlapping.
TranscriptCue? transcriptCueAt(List<TranscriptCue> cues, Duration position) {
  return EpisodeTranscript.findCueAt(cues, position);
}
