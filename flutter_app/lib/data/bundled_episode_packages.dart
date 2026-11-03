import 'package:flutter/services.dart';

import '../models/catalogue.dart';
import '../models/episode_package.dart';
import '../models/episode_transcript.dart';
import 'episode_package_repository.dart';

/// The single registration point for bundled episode resources.
class BundledEpisodePackages {
  static const karooGuid =
      'commondescentpodcast.podbean.com/870afb21-277f-398e-ba55-6e50d68ceda6';
  static const karooPackageAsset =
      'assets/episodes/870afb21-277f-398e-ba55-6e50d68ceda6';
  static const karooAudioAsset = '$karooPackageAsset/audio.opus';
  static const karooReviewedAsset =
      '$karooPackageAsset/transcript/baseline.json';
  static const karooAlignmentAsset =
      '$karooPackageAsset/transcript/alignment.json';
  static const karooManifestAsset = '$karooPackageAsset/episode.json';
  static const karooAudioSha256 =
      'b1d4fc7089dda6b9c1f5f42b8887ddc267a4305b47da0fab95f2507bcc6ee38d';
  static const karooSourceSha256 =
      '05920194f6cb7411cb69bfc8e1aafb348a7d84b25607104bc40f4631d134036b';
  static const karooAudioIdentity = 'sha256:$karooAudioSha256';

  // Lightweight bootstrap for the published manifest. Transcript loading checks
  // these fields against episode.json before opening this edition's timings.
  static final karoo = EpisodePackageResources(
    key: '870afb21-277f-398e-ba55-6e50d68ceda6',
    episodeGuid: karooGuid,
    manifestAsset: karooManifestAsset,
    audio: EpisodeAudioEdition(
      sha256: karooAudioSha256,
      assetPath: karooAudioAsset,
      codec: EpisodeAudioCodec.opus,
      duration: const Duration(milliseconds: 6543509),
      byteLength: 13954279,
      targetBitrate: 16000,
      sourceSha256: karooSourceSha256,
    ),
    transcript: EpisodeTranscriptAssets(
      reviewedAsset: karooReviewedAsset,
      alignmentAsset: karooAlignmentAsset,
      passageCount: 1032,
    ),
  );

  static const plesiosaursGuid =
      'commondescentpodcast.podbean.com/episode-72-plesiosaurs-d111dc1276ec736e782a70ac43fed94c';
  static const plesiosaursPackageAsset =
      'assets/episodes/d111dc1276ec736e782a70ac43fed94c';
  static const plesiosaursManifestAsset =
      '$plesiosaursPackageAsset/episode.json';

  static final plesiosaurs = EpisodePackageResources(
    key: 'd111dc1276ec736e782a70ac43fed94c',
    episodeGuid: plesiosaursGuid,
    manifestAsset: plesiosaursManifestAsset,
    audio: EpisodeAudioEdition(
      sha256:
          'a8bc989316f5c4193f20862a814a5e08f0e239631052955f4bba6d819c7c729c',
      assetPath: '$plesiosaursPackageAsset/audio.opus',
      codec: EpisodeAudioCodec.opus,
      duration: const Duration(milliseconds: 6150245),
      byteLength: 13248456,
      targetBitrate: 16000,
      sourceSha256:
          '27e9cb16996244d066f907658b110eaf5861ca7c76de9ac38a5c2929d8d5d53d',
    ),
    transcript: EpisodeTranscriptAssets(
      reviewedAsset: '$plesiosaursPackageAsset/transcript/baseline.json',
      alignmentAsset: '$plesiosaursPackageAsset/transcript/alignment.json',
      passageCount: 990,
    ),
  );

  static const wallaceGuid =
      'commondescentpodcast.podbean.com/episode-54-alfred-russell-wallace-6db090f54c04b34e2f1abdfefcb67c97';
  static const wallacePackageAsset =
      'assets/episodes/6db090f54c04b34e2f1abdfefcb67c97';
  static const wallaceManifestAsset = '$wallacePackageAsset/episode.json';

  static final wallace = EpisodePackageResources(
    key: '6db090f54c04b34e2f1abdfefcb67c97',
    episodeGuid: wallaceGuid,
    manifestAsset: wallaceManifestAsset,
    audio: EpisodeAudioEdition(
      sha256:
          '0a84252286eb021e8dbebdcd8044ac3f5dd5c8dc5a580ef06cfc384761e1845c',
      assetPath: '$wallacePackageAsset/audio.opus',
      codec: EpisodeAudioCodec.opus,
      duration: const Duration(milliseconds: 7344889),
      byteLength: 16286994,
      targetBitrate: 16000,
      sourceSha256:
          '1c088dffc4b947ca723e8e78bfc760e3cba99a0c266c92270700cec31b1d8bb4',
    ),
    transcript: EpisodeTranscriptAssets(
      reviewedAsset: '$wallacePackageAsset/transcript/baseline.json',
      alignmentAsset: '$wallacePackageAsset/transcript/alignment.json',
      passageCount: 1117,
    ),
  );

  static final preparedEpisodeE0cf7edb94643ca5 = EpisodePackageResources(
    key: "8d867b7228cb",
    episodeGuid:
        "commondescentpodcast.podbean.com/5f3761f0-97c3-5372-90d5-8d867b7228cb",
    manifestAsset: "assets/episodes/8d867b7228cb/episode.json",
    audio: EpisodeAudioEdition(
      sha256:
          "f4d1946b5d4c75fd0bb5d6f5a767ace858c0c61f9b0badbfa6cc90c6def41903",
      assetPath: "assets/episodes/8d867b7228cb/audio.opus",
      codec: EpisodeAudioCodec.opus,
      duration: const Duration(milliseconds: 6188362),
      byteLength: 12907572,
      targetBitrate: 16000,
      sourceSha256:
          "7985626683a1ed5d07bc2eed15bd27de79aba4d182179ce48d82578ba8cf2c27",
    ),
    transcript: EpisodeTranscriptAssets(
      reviewedAsset: "assets/episodes/8d867b7228cb/transcript/baseline.json",
      alignmentAsset: "assets/episodes/8d867b7228cb/transcript/alignment.json",
      passageCount: 1197,
    ),
  );

  static final _repository = EpisodePackageRepository(
    resources: [karoo, plesiosaurs, wallace, preparedEpisodeE0cf7edb94643ca5],
    loadText: (assetPath) => rootBundle.loadString(assetPath),
  );

  static EpisodePackage forEpisode(Episode episode) =>
      _repository.resolve(episode);

  static bool hasTranscript(String guid) => _repository.hasTranscript(guid);

  static Future<EpisodeTranscript> loadTranscript(String guid) =>
      _repository.loadTranscript(guid);
}
