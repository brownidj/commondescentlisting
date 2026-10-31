import 'package:yaml/yaml.dart';

import '../models/catalogue.dart';

/// Rejects invalid input as a whole; no records are silently discarded.
class CatalogueParser {
  CatalogueData parse(String source, {String sourceName = 'YAML catalogue'}) {
    try {
      return _parse(source);
    } on YamlException catch (error) {
      throw FormatException('$sourceName: invalid YAML: $error');
    } on FormatException catch (error) {
      throw FormatException('$sourceName: ${error.message}');
    }
  }

  CatalogueData _parse(String source) {
    final root = _map(loadYaml(source), 'document');
    // Unversioned files are the existing legacy v1 contract.
    if (root.containsKey('schema_version') && root['schema_version'] != 1) {
      throw const FormatException(
        'schema_version: only legacy v1 is supported',
      );
    }
    final podcast = _map(root['podcast'], 'podcast');
    final rawSegments = root['segments'];
    if (rawSegments is! List) {
      throw const FormatException('segments: expected a list');
    }
    final segments = <Segment>[];
    for (var index = 0; index < rawSegments.length; index++) {
      final path = 'segments[$index] (record ${index + 1})';
      final row = _map(rawSegments[index], path);
      final number = row['episode_number'];
      if (number != null &&
          number is! String &&
          number is! int &&
          !(number is double && number.isFinite)) {
        throw FormatException(
          '$path.episode_number: expected a string or number, or null',
        );
      }
      final review = row['needs_review'];
      if (review != null && review is! bool) {
        throw FormatException('$path.needs_review: expected a boolean or null');
      }
      segments.add(
        Segment(
          sourceIndex: index,
          guid: _required(row, 'guid', path),
          episodeTitle: _required(row, 'episode_title', path),
          episodeNumber: number?.toString(),
          type: _required(row, 'segment_type', path),
          title: _optional(row, 'segment_title', path),
          label: _optional(row, 'segment_label', path),
          sourceUrl: _optional(row, 'source_url', path),
          startTime: _timestamp(row, 'start_time', path),
          newsStartTime: _timestamp(row, 'news_start_time', path),
          newsRaw: _optional(row, 'news_raw', path),
          needsReview: review as bool?,
          headlineSplitMethod: _optional(row, 'headline_split_method', path),
        ),
      );
    }
    return CatalogueData(
      podcast: Podcast(
        title: _required(podcast, 'title', 'podcast'),
        rss: _optional(podcast, 'rss', 'podcast'),
      ),
      segments: segments,
    );
  }

  Map<dynamic, dynamic> _map(Object? value, String path) {
    if (value is! Map) throw FormatException('$path: expected a mapping');
    return value;
  }

  String _required(Map<dynamic, dynamic> row, String key, String path) {
    final value = _optional(row, key, path);
    if (value == null || value.trim().isEmpty) {
      throw FormatException('$path.$key: expected a non-empty string');
    }
    return value;
  }

  String? _optional(Map<dynamic, dynamic> row, String key, String path) {
    final value = row[key];
    if (value != null && value is! String) {
      throw FormatException('$path.$key: expected a string or null');
    }
    return value as String?;
  }

  Duration? _timestamp(Map<dynamic, dynamic> row, String key, String path) {
    final value = _optional(row, key, path);
    if (value == null) return null;
    if (!RegExp(r'^\d+:\d{2}(?::\d{2})?$').hasMatch(value)) {
      throw FormatException('$path.$key: expected MM:SS or HH:MM:SS');
    }
    final parts = value.split(':').map(int.tryParse).toList();
    if (parts.any((part) => part == null)) {
      throw FormatException('$path.$key: timestamp is out of range');
    }
    final seconds = parts.last!;
    final minutes = parts[parts.length - 2]!;
    final hours = parts.length == 3 ? parts.first! : 0;
    if (seconds > 59 || (parts.length == 3 && minutes > 59)) {
      throw FormatException('$path.$key: minutes/seconds out of range');
    }
    // Bound arithmetic before constructing Duration (microseconds use an int).
    final total =
        BigInt.from(hours) * BigInt.from(3600) +
        BigInt.from(minutes) * BigInt.from(60) +
        BigInt.from(seconds);
    if (total > BigInt.from(2147483647)) {
      throw FormatException('$path.$key: timestamp is out of range');
    }
    return Duration(seconds: total.toInt());
  }
}
