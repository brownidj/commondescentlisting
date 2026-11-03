import '../data/bundled_transcripts.dart';
import '../data/bundled_episode_packages.dart';
import '../data/local_prepared_episodes.dart';
import '../models/catalogue.dart';
import '../models/episode_transcript.dart';
import 'file_transcript_edits.dart';
import 'transcript_edits.dart';

class CurrentTranscript {
  const CurrentTranscript({
    required this.episode,
    required this.transcript,
    required this.edition,
    required this.syncOffset,
  });
  final Episode episode;
  final EpisodeTranscript transcript;
  final String edition;
  final Duration syncOffset;
  Duration audioStart(TranscriptCue cue) {
    final time = cue.start - syncOffset;
    return time.isNegative ? Duration.zero : time;
  }
}

Future<CurrentTranscript> loadCurrentTranscript(Episode episode) async {
  final local = LocalPreparedEpisodes.forGuid(episode.guid);
  final baseline = await BundledTranscripts.load(episode.guid);
  final edits = TranscriptEdits(
    baseline: baseline,
    store: local?.readOnly == true
        ? ReadOnlyTranscriptEditStore()
        : FileTranscriptEditStore(editionKey: local?.edition),
  );
  try {
    await edits.load();
    if (!edits.ready || edits.conflict || edits.loadError != null) {
      throw StateError(edits.loadError ?? 'Corrections unavailable.');
    }
    if (LocalPreparedEpisodes.forGuid(episode.guid)?.edition !=
        local?.edition) {
      throw StateError('Transcript edition changed while loading; try again.');
    }
    return CurrentTranscript(
      episode: episode,
      transcript: edits.current,
      edition: local?.edition ?? baseline.audioIdentity ?? 'bundled',
      syncOffset: edits.syncOffset,
    );
  } finally {
    edits.dispose();
  }
}

bool currentTranscriptAudioMatches(CurrentTranscript document) {
  final local = LocalPreparedEpisodes.forGuid(document.episode.guid);
  final identity =
      local?.audioIdentity ??
      BundledEpisodePackages.forEpisode(document.episode)
          .audioEdition
          ?.identity;
  return identity != null &&
      identity == document.transcript.audioIdentity &&
      document.edition ==
          (local?.edition ?? document.transcript.audioIdentity ?? 'bundled');
}
