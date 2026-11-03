import '../models/catalogue.dart';
import 'bundled_episode_packages.dart';
import 'local_prepared_episodes.dart';

/// Fixed audio editions keep acoustic transcript timings independent of adverts.
class EpisodeAudio {
  static const karooGuid = BundledEpisodePackages.karooGuid;
  static const karooAsset = BundledEpisodePackages.karooAudioAsset;
  static const karooIdentity = BundledEpisodePackages.karooAudioIdentity;

  static Uri? sourceFor(Episode episode) =>
      LocalPreparedEpisodes.forGuid(episode.guid)?.audioUri ??
      BundledEpisodePackages.forEpisode(episode).playbackUri;
}
