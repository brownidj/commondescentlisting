import '../models/episode_transcript.dart';
import 'bundled_episode_packages.dart';
import 'local_prepared_episodes.dart';

class BundledTranscripts {
  static const episode208Guid = BundledEpisodePackages.karooGuid;

  static bool hasEpisode(String guid) =>
      LocalPreparedEpisodes.forGuid(guid) != null ||
      BundledEpisodePackages.hasTranscript(guid);

  static Future<EpisodeTranscript> load(String guid) =>
      LocalPreparedEpisodes.forGuid(guid)?.loadTranscript() ??
      BundledEpisodePackages.loadTranscript(guid);
}
