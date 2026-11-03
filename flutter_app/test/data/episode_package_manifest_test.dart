import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/bundled_episode_packages.dart';
import 'package:common_descent_listing/data/episode_package_repository.dart';
import 'package:common_descent_listing/models/episode_package.dart';
import 'package:common_descent_listing/models/episode_package_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _document() => jsonDecode(
  File(BundledEpisodePackages.karooManifestAsset).readAsStringSync(),
) as Map<String, dynamic>;

void main() {
  test('published Karoo manifest matches registration and listed files', () {
    final source = File(BundledEpisodePackages.karooManifestAsset)
        .readAsStringSync();
    final manifest = EpisodePackageManifest.parse(
      source,
      manifestAsset: BundledEpisodePackages.karooManifestAsset,
    );
    expect(manifest.matches(BundledEpisodePackages.karoo), isTrue);
    expect(manifest.title, 'The Karoo Supergroup');
    expect(manifest.resources.audio!.codec, EpisodeAudioCodec.opus);
    expect(manifest.resources.audio!.targetBitrate, 16000);
    expect(
      manifest.resources.audio!.sourceSha256,
      BundledEpisodePackages.karooSourceSha256,
    );
    final document = _document();
    for (final entry in document['artifacts'] as List) {
      final row = entry as Map<String, dynamic>;
      final file = File(
        '${BundledEpisodePackages.karooPackageAsset}/${row['file']}',
      );
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), row['byte_length']);
    }
  });

  test('resource paths must stay within the package directory', () {
    for (final path in [
      '../source.mp3',
      '/tmp/source.mp3',
      'https://example.com/audio.opus',
      'transcript/%2e%2e/source.mp3',
      'audio.opus?edition=other',
    ]) {
      final document = _document();
      (document['audio'] as Map<String, dynamic>)['file'] = path;
      expect(
        () => EpisodePackageManifest.parse(
          jsonEncode(document),
          manifestAsset: BundledEpisodePackages.karooManifestAsset,
        ),
        throwsFormatException,
      );
    }
  });

  test('schema and self-inconsistent audio identity are rejected', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (document) => document['schema_version'] = 2,
      (document) => document['audio']['identity'] = 'sha256:other',
    ]) {
      final document = _document();
      change(document);
      expect(
        () => EpisodePackageManifest.parse(
          jsonEncode(document),
          manifestAsset: BundledEpisodePackages.karooManifestAsset,
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'stale bootstrap metadata fails before any transcript is loaded',
    () async {
      final document = _document();
      document['audio']['duration_ms'] += 1000;
      final reads = <String>[];
      final repository = EpisodePackageRepository(
        resources: [BundledEpisodePackages.karoo],
        loadText: (path) async {
          reads.add(path);
          if (path != BundledEpisodePackages.karooManifestAsset) {
            throw StateError(
              'A stale package must not load transcript assets.',
            );
          }
          return jsonEncode(document);
        },
      );
      await expectLater(
        repository.loadTranscript(BundledEpisodePackages.karooGuid),
        throwsFormatException,
      );
      expect(reads, [BundledEpisodePackages.karooManifestAsset]);
    },
  );
}
