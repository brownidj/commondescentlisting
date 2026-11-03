import 'catalogue.dart';

enum EpisodeAudioCodec { mp3, aac, opus }

void _requireSha256(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, 'sha256', 'Expected a lowercase SHA-256.');
  }
}

void _requireAssetPath(String value) {
  final uri = Uri.tryParse(value);
  if (!value.startsWith('assets/') ||
      value.contains('\\') ||
      uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path != value ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(
      value,
      'assetPath',
      'Expected a bundle asset path.',
    );
  }
}

/// The retained playback recording, not a temporary publisher download.
/// Hash verification belongs to publishing/import, before registering an edition.
class EpisodeAudioEdition {
  EpisodeAudioEdition({
    required this.sha256,
    required this.assetPath,
    required this.codec,
    required this.duration,
    required this.byteLength,
    this.targetBitrate,
    this.sourceSha256,
  }) {
    _requireSha256(sha256);
    _requireAssetPath(assetPath);
    if (sourceSha256 != null) {
      _requireSha256(sourceSha256!);
    }
    if (duration <= Duration.zero ||
        byteLength <= 0 ||
        (targetBitrate != null && targetBitrate! <= 0)) {
      throw ArgumentError('Audio duration, size and bitrate must be positive.');
    }
  }

  final String sha256;
  final String assetPath;
  final EpisodeAudioCodec codec;
  final Duration duration;
  final int byteLength;
  final int? targetBitrate;

  /// Provenance only. No source-download file or path is part of a package.
  final String? sourceSha256;

  String get identity => 'sha256:$sha256';
  Uri get uri => Uri(scheme: 'asset', path: '/$assetPath');
}

/// File references stay lightweight; reviewed text is loaded only on demand.
class EpisodeTranscriptAssets {
  EpisodeTranscriptAssets({
    required this.reviewedAsset,
    required this.passageCount,
    this.alignmentAsset,
  }) {
    _requireAssetPath(reviewedAsset);
    if (alignmentAsset != null) {
      _requireAssetPath(alignmentAsset!);
    }
    if (passageCount <= 0) {
      throw ArgumentError.value(passageCount, 'passageCount');
    }
  }

  final String reviewedAsset;
  final String? alignmentAsset;
  final int passageCount;
}

/// Registration of an episode's active resource pair, shared by both loaders.
class EpisodePackageResources {
  EpisodePackageResources({
    required this.key,
    required this.episodeGuid,
    this.manifestAsset,
    this.audio,
    this.transcript,
  }) {
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]*$').hasMatch(key) ||
        episodeGuid.trim().isEmpty ||
        (audio == null && transcript == null)) {
      throw ArgumentError('Episode resource identity or contents are invalid.');
    }
    if (transcript?.alignmentAsset != null && audio == null) {
      throw ArgumentError('An alignment requires its matching audio edition.');
    }
    if (manifestAsset != null) {
      _requireAssetPath(manifestAsset!);
    }
  }

  /// Stable storage key; independent of titles and display episode numbers.
  final String key;
  final String episodeGuid;
  final String? manifestAsset;
  final EpisodeAudioEdition? audio;
  final EpisodeTranscriptAssets? transcript;
}

/// One instance combines catalogue metadata with its registered local resources.
/// Transcript corrections remain in the existing GUID-keyed listener journal.
class EpisodePackage {
  EpisodePackage({required this.episode, this.resources}) {
    if (resources != null && resources!.episodeGuid != episode.guid) {
      throw ArgumentError('Episode resources belong to a different episode.');
    }
  }

  final Episode episode;
  final EpisodePackageResources? resources;

  EpisodeAudioEdition? get audioEdition => resources?.audio;
  bool get hasTranscript => resources?.transcript != null;
  Uri? get playbackUri => audioEdition?.uri ?? episode.audioUri;

  /// Only an explicit future maintenance operation should download this source.
  /// Episodes without local audio keep their existing streaming behaviour.
  Uri? get sourceDownloadUri => episode.audioUri;
}
