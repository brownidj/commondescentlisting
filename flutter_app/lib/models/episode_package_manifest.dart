import 'dart:convert';

import 'episode_package.dart';

/// Portable package metadata. Paths resolve relative to the manifest's folder.
class EpisodePackageManifest {
  EpisodePackageManifest._({required this.resources, required this.title});

  final EpisodePackageResources resources;
  final String title;

  factory EpisodePackageManifest.parse(
    String source, {
    required String manifestAsset,
  }) {
    try {
      final root = _map(jsonDecode(source));
      if (root['schema_version'] != 1) {
        throw const FormatException('Unsupported episode package schema.');
      }
      final directory = manifestAsset.substring(
        0,
        manifestAsset.lastIndexOf('/') + 1,
      );
      String asset(Object? file) {
        if (file is! String ||
            file.isEmpty ||
            file.contains('\\') ||
            file.contains('%') ||
            file
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..')) {
          throw const FormatException(
            'Invalid package-relative resource path.',
          );
        }
        final uri = Uri.tryParse(file);
        if (uri == null ||
            uri.hasScheme ||
            uri.hasAuthority ||
            uri.hasQuery ||
            uri.hasFragment) {
          throw const FormatException(
            'Invalid package-relative resource path.',
          );
        }
        return '$directory$file';
      }

      final audio = _map(root['audio']);
      final transcript = _map(root['transcript']);
      final metadata = _map(root['metadata']);
      final codec = switch (audio['codec']) {
        'mp3' => EpisodeAudioCodec.mp3,
        'aac' => EpisodeAudioCodec.aac,
        'opus' => EpisodeAudioCodec.opus,
        _ => throw const FormatException('Unknown episode audio codec.'),
      };
      final edition = EpisodeAudioEdition(
        sha256: _value<String>(audio, 'sha256'),
        assetPath: asset(audio['file']),
        codec: codec,
        duration: Duration(milliseconds: _value<int>(audio, 'duration_ms')),
        byteLength: _value<int>(audio, 'byte_length'),
        targetBitrate: audio['target_bitrate'] == null
            ? null
            : _value<int>(audio, 'target_bitrate'),
        sourceSha256: audio['source_sha256'] == null
            ? null
            : _value<String>(audio, 'source_sha256'),
      );
      if (audio['identity'] != edition.identity) {
        throw const FormatException('Package audio identity is inconsistent.');
      }
      for (final field in [
        'words_file',
        'listener_file',
        'text_file',
        'vtt_file',
        'srt_file',
      ]) {
        if (transcript[field] != null) {
          asset(transcript[field]);
        }
      }
      for (final field in ['segments_file', 'provenance_file']) {
        if (root[field] != null) {
          asset(root[field]);
        }
      }
      final title = _value<String>(metadata, 'title');
      if (title.trim().isEmpty) {
        throw const FormatException('Episode package title is empty.');
      }
      return EpisodePackageManifest._(
        title: title,
        resources: EpisodePackageResources(
          key: _value<String>(root, 'key'),
          episodeGuid: _value<String>(root, 'episode_guid'),
          manifestAsset: manifestAsset,
          audio: edition,
          transcript: EpisodeTranscriptAssets(
            reviewedAsset: asset(transcript['reviewed_file']),
            alignmentAsset: transcript['alignment_file'] == null
                ? null
                : asset(transcript['alignment_file']),
            passageCount: _value<int>(transcript, 'passage_count'),
          ),
        ),
      );
    } on ArgumentError catch (_) {
      throw const FormatException(
        'Episode package resource metadata is invalid.',
      );
    }
  }

  /// The synchronous bootstrap registration must describe this same edition.
  bool matches(EpisodePackageResources registered) {
    final audio = resources.audio!;
    final otherAudio = registered.audio;
    final transcript = resources.transcript!;
    final otherTranscript = registered.transcript;
    if (otherAudio == null || otherTranscript == null) {
      return false;
    }
    return resources.key == registered.key &&
        resources.episodeGuid == registered.episodeGuid &&
        resources.manifestAsset == registered.manifestAsset &&
        audio.identity == otherAudio.identity &&
        audio.assetPath == otherAudio.assetPath &&
        audio.codec == otherAudio.codec &&
        audio.duration == otherAudio.duration &&
        audio.byteLength == otherAudio.byteLength &&
        audio.targetBitrate == otherAudio.targetBitrate &&
        audio.sourceSha256 == otherAudio.sourceSha256 &&
        transcript.reviewedAsset == otherTranscript.reviewedAsset &&
        transcript.alignmentAsset == otherTranscript.alignmentAsset &&
        transcript.passageCount == otherTranscript.passageCount;
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Episode package expects an object.');
  }
  return value;
}

T _value<T>(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! T) {
    throw FormatException('Invalid episode package field: $key.');
  }
  return value;
}
