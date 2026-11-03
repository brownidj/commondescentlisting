import '../models/catalogue.dart';
import '../models/episode_package.dart';
import '../models/episode_package_manifest.dart';
import '../models/episode_transcript.dart';
import '../models/transcript_alignment.dart';

class EpisodePackageRepository {
  EpisodePackageRepository({
    required Iterable<EpisodePackageResources> resources,
    required this.loadText,
  }) {
    final byGuid = <String, EpisodePackageResources>{};
    final keys = <String>{};
    for (final resource in resources) {
      if (byGuid.containsKey(resource.episodeGuid) || !keys.add(resource.key)) {
        throw ArgumentError('Duplicate episode resource GUID or storage key.');
      }
      byGuid[resource.episodeGuid] = resource;
    }
    _resources = Map.unmodifiable(byGuid);
  }

  late final Map<String, EpisodePackageResources> _resources;
  final Future<String> Function(String assetPath) loadText;

  /// Resolving a package performs no I/O and does not load the audio/transcript.
  EpisodePackage resolve(Episode episode) =>
      EpisodePackage(episode: episode, resources: _resources[episode.guid]);

  bool hasTranscript(String guid) => _resources[guid]?.transcript != null;

  Future<EpisodeTranscript> loadTranscript(String guid) async {
    final resource = _resources[guid];
    final assets = resource?.transcript;
    if (resource == null || assets == null) {
      throw const FormatException('No reviewed transcript for this episode.');
    }
    final manifestAsset = resource.manifestAsset;
    if (manifestAsset != null) {
      final manifest = EpisodePackageManifest.parse(
        await loadText(manifestAsset),
        manifestAsset: manifestAsset,
      );
      if (!manifest.matches(resource)) {
        throw const FormatException('Episode package registration is stale.');
      }
    }
    var transcript = EpisodeTranscript.parse(
      await loadText(assets.reviewedAsset),
      episodeGuid: guid,
    );
    final alignmentAsset = assets.alignmentAsset;
    final audio = resource.audio;
    if (alignmentAsset != null && audio != null) {
      transcript = applyTranscriptAlignment(
        transcript,
        await loadText(alignmentAsset),
        audioIdentity: audio.identity,
        audioDuration: audio.duration,
      );
    }
    if (transcript.cues.length != assets.passageCount) {
      throw const FormatException(
        'Episode transcript passage count is invalid.',
      );
    }
    if (audio != null &&
        (transcript.audioIdentity != audio.identity ||
            transcript.cues.last.end > audio.duration)) {
      throw const FormatException(
        'Transcript does not match the audio edition.',
      );
    }
    return transcript;
  }
}
