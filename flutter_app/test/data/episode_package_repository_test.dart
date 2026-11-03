import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/bundled_episode_packages.dart';
import 'package:common_descent_listing/data/episode_audio.dart';
import 'package:common_descent_listing/data/episode_package_repository.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_package.dart';
import 'package:flutter_test/flutter_test.dart';

const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Episode _episode(String guid) => Episode(
  guid: guid,
  title: 'Example episode',
  number: '208',
  segments: [
    Segment(
      sourceIndex: 0,
      guid: guid,
      episodeTitle: 'Example episode',
      type: 'News',
      audioUrl: 'https://example.com/publisher-recording.mp3',
    ),
  ],
);

EpisodePackageResources _resources({
  String guid = 'example',
  String key = 'example',
  int passages = 2,
}) => EpisodePackageResources(
  key: key,
  episodeGuid: guid,
  audio: EpisodeAudioEdition(
    sha256: _digest,
    assetPath: 'assets/episodes/example/audio.opus',
    codec: EpisodeAudioCodec.opus,
    duration: const Duration(seconds: 5),
    byteLength: 11000,
    targetBitrate: 16000,
  ),
  transcript: EpisodeTranscriptAssets(
    reviewedAsset: 'assets/episodes/example/transcript.json',
    alignmentAsset: 'assets/episodes/example/alignment.json',
    passageCount: passages,
  ),
);

Map<String, dynamic> _baseline() => {
  'schema_version': 1,
  'episode_guid': 'example',
  'review': {'label': 'Reviewed', 'note': 'Contextual corrections.'},
  'changes': [],
  'unresolved': [],
  'segments': [
    {'id': 1, 'start_ms': 0, 'end_ms': 1000, 'text': 'Hello.'},
    {'id': 2, 'start_ms': 1000, 'end_ms': 2000, 'text': 'Karoo.'},
  ],
};

Map<String, dynamic> _alignment() => {
  'schema_version': 1,
  'episode_guid': 'example',
  'audio_identity': 'sha256:$_digest',
  'audio_duration_ms': 5000,
  'segments': [
    {
      'id': 1,
      'source_start_ms': 0,
      'source_end_ms': 1000,
      'start_ms': 200,
      'end_ms': 1100,
      'baseline_text': 'Hello.',
      'review_flags': [],
    },
    {
      'id': 2,
      'source_start_ms': 1000,
      'source_end_ms': 2000,
      'start_ms': 1200,
      'end_ms': 2200,
      'baseline_text': 'Karoo.',
      'review_flags': [],
    },
  ],
};

void main() {
  test('resolve is lazy; unknown episodes preserve streaming and segments', () {
    final repository = EpisodePackageRepository(
      resources: [_resources()],
      loadText: (_) => throw StateError('Resolving must not read assets.'),
    );
    final local = repository.resolve(_episode('example'));
    expect(local.playbackUri?.scheme, 'asset');
    expect(local.hasTranscript, isTrue);
    final episode = _episode('other');
    final remote = repository.resolve(episode);
    expect(identical(remote.episode, episode), isTrue);
    expect(remote.episode.segments.single.isNews, isTrue);
    expect(remote.playbackUri, episode.audioUri);
    expect(remote.hasTranscript, isFalse);
    expect(remote.resources, isNull);
    expect(local.sourceDownloadUri?.scheme, 'https');
  });

  test(
    'actual Karoo registration loads its complete matching transcript',
    () async {
      final reads = <String>[];
      final repository = EpisodePackageRepository(
        resources: [BundledEpisodePackages.karoo],
        loadText: (asset) async {
          reads.add(asset);
          return File(asset).readAsString();
        },
      );
      final package = repository.resolve(
        _episode(BundledEpisodePackages.karooGuid),
      );
      expect(reads, isEmpty);
      expect(package.playbackUri, EpisodeAudio.sourceFor(package.episode));
      final transcript = await repository.loadTranscript(package.episode.guid);
      expect(transcript.audioIdentity, package.audioEdition!.identity);
      expect(transcript.cues, hasLength(1032));
      expect(transcript.cues.first.revisionStart, Duration.zero);
      expect(transcript.cues.first.start, lessThan(const Duration(seconds: 3)));
      expect(
        transcript.cues.last.end,
        lessThan(package.audioEdition!.duration),
      );
      expect(reads, [
        BundledEpisodePackages.karoo.manifestAsset,
        BundledEpisodePackages.karoo.transcript!.reviewedAsset,
        BundledEpisodePackages.karoo.transcript!.alignmentAsset,
      ]);
    },
  );

  test(
    'wrong GUID, audio identity or audio duration cannot share timings',
    () async {
      for (final changed in [
        {..._alignment(), 'episode_guid': 'other'},
        {..._alignment(), 'audio_identity': 'sha256:different'},
        {..._alignment(), 'audio_duration_ms': 6000},
      ]) {
        final resource = _resources();
        final repository = EpisodePackageRepository(
          resources: [resource],
          loadText: (asset) async => jsonEncode(
            asset == resource.transcript!.reviewedAsset ? _baseline() : changed,
          ),
        );
        await expectLater(
          repository.loadTranscript('example'),
          throwsFormatException,
        );
      }
    },
  );

  for (final resource in [
    BundledEpisodePackages.plesiosaurs,
    BundledEpisodePackages.wallace,
  ]) {
    test(
      '${resource.key} loads its own unreviewed text and audio edition',
      () async {
        final reads = <String>[];
        final repository = EpisodePackageRepository(
          resources: [BundledEpisodePackages.karoo, resource],
          loadText: (asset) async {
            reads.add(asset);
            return File(asset).readAsString();
          },
        );
        final package = repository.resolve(_episode(resource.episodeGuid));
        expect(package.resources, same(resource));
        expect(package.playbackUri, resource.audio!.uri);
        final transcript = await repository.loadTranscript(
          resource.episodeGuid,
        );
        final baseline = jsonDecode(
          File(resource.transcript!.reviewedAsset).readAsStringSync(),
        ) as Map<String, dynamic>;
        final segments = baseline['segments'] as List;
        expect(transcript.episodeGuid, resource.episodeGuid);
        expect(transcript.label, 'Machine transcribed; not reviewed.');
        expect(transcript.audioIdentity, resource.audio!.identity);
        expect(
          transcript.audioIdentity,
          isNot(BundledEpisodePackages.karooAudioIdentity),
        );
        expect(transcript.cues, hasLength(resource.transcript!.passageCount));
        for (var index = 0; index < transcript.cues.length; index++) {
          final raw = segments[index] as Map<String, dynamic>;
          expect(transcript.cues[index].id, raw['id']);
          expect(transcript.cues[index].text, raw['text']);
          expect(
            transcript.cues[index].revisionStart.inMilliseconds,
            raw['start_ms'],
          );
        }
        expect(
          transcript.cues.last.end,
          lessThanOrEqualTo(resource.audio!.duration),
        );
        expect(reads, [
          resource.manifestAsset,
          resource.transcript!.reviewedAsset,
          resource.transcript!.alignmentAsset,
        ]);
      },
    );
  }

  test('coverage metadata and missing transcripts fail explicitly', () async {
    final resource = _resources(passages: 3);
    var reads = 0;
    final repository = EpisodePackageRepository(
      resources: [resource],
      loadText: (asset) async {
        reads++;
        return jsonEncode(
          asset == resource.transcript!.reviewedAsset
              ? _baseline()
              : _alignment(),
        );
      },
    );
    await expectLater(
      repository.loadTranscript('example'),
      throwsFormatException,
    );
    expect(reads, 2);
    await expectLater(
      repository.loadTranscript('missing'),
      throwsFormatException,
    );
    expect(reads, 2);
  });

  test('registry collisions and cross-episode aggregates are rejected', () {
    for (final duplicate in [
      _resources(key: 'different'),
      _resources(guid: 'different'),
    ]) {
      expect(
        () => EpisodePackageRepository(
          resources: [_resources(), duplicate],
          loadText: (_) async => '',
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => EpisodePackage(episode: _episode('other'), resources: _resources()),
      throwsArgumentError,
    );
    expect(
      () => EpisodeAudioEdition(
        sha256: _digest,
        assetPath: 'assets/episodes/../source.mp3',
        codec: EpisodeAudioCodec.mp3,
        duration: const Duration(seconds: 1),
        byteLength: 100,
      ),
      throwsArgumentError,
    );
  });
}
