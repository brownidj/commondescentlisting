import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;
import 'package:http_parser/http_parser.dart';
import 'package:xml/xml.dart';

import '../models/catalogue.dart';
import 'local_catalogue.dart';

typedef CatalogueProgress = void Function(String stage, double? fraction);
typedef CatalogueRefresh = Future<String?> Function(
  Catalogue current,
  CatalogueProgress progress,
);

/// Metadata only: audio, transcript editions and indexes are never replaced here.
class PodcastFeedCatalogue {
  static final feed = Uri.parse(
    'https://commondescentpodcast.podbean.com/feed',
  );

  Future<String> refresh(Catalogue current, CatalogueProgress progress) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await (() async {
        progress('Checking podcast catalogue', null);
        final request = await client.getUrl(feed);
        request.headers.set(HttpHeaders.userAgentHeader, 'CDList/0.1');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Podcast feed returned ${response.statusCode}.');
        }
        // The RSS contains full show notes and is larger than the segment file.
        const limit = 20 * 1024 * 1024;
        if (response.contentLength > limit) {
          throw const FormatException('Podcast feed exceeds 20 MiB.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final part in response) {
          if (bytes.length + part.length > limit) {
            throw const FormatException('Podcast feed exceeds 20 MiB.');
          }
          bytes.add(part);
          progress(
            'Downloading catalogue update',
            response.contentLength > 0
                ? (bytes.length / response.contentLength).clamp(0.0, 1.0)
                : null,
          );
        }
        progress('Reading podcast metadata', null);
        return mergeFeed(utf8.decode(bytes.takeBytes()), current);
      })().timeout(const Duration(seconds: 35));
    } finally {
      client.close(force: true);
    }
  }

  /// Follow the existing generator's headline/time rules and preserve older GUIDs
  /// when the publisher supplies only a recent window of its archive.
  String mergeFeed(String source, Catalogue current) {
    final document = XmlDocument.parse(source);
    final channel = document.getElement('rss')?.getElement('channel');
    if (channel == null) {
      throw const FormatException('Expected a podcast RSS feed.');
    }
    final items = channel.findElements('item').toList();
    if (items.isEmpty) {
      throw const FormatException('Podcast feed contains no episodes.');
    }
    final fresh = <String, List<Map<String, Object?>>>{};
    for (final item in items) {
      final guid = _text(item, 'guid');
      final title = _text(item, 'title');
      if (guid == null || title == null || fresh.containsKey(guid)) {
        throw const FormatException(
          'Missing or duplicate podcast episode identity.',
        );
      }
      final number = RegExp(
        r'^Episode\s+(\d+(?:\.\d+)?[A-Za-z]?)\s*[-–—:]\s*(.*)$',
        caseSensitive: false,
      ).firstMatch(title);
      final description = _description(_text(item, 'description') ?? '');
      final common = <String, Object?>{
        'guid': guid,
        'episode_number': number?.group(1),
        'episode_title': number?.group(2) ?? title,
        'episode_published_at': _date(_text(item, 'pubDate')),
        'source_url': _text(item, 'link'),
        'audio_url': item.getElement('enclosure')?.getAttribute('url'),
      };
      final summary = RegExp(
        r'^In the news\s*:\s*([^\n]+)',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(description)?.group(1);
      final time = RegExp(
        r'^News\s*:\s*(\d{1,2}:\d{2}(?::\d{2})?)\b',
        multiLine: true,
        caseSensitive: false,
      ).firstMatch(description)?.group(1);
      final rows = <Map<String, Object?>>[];
      if (summary != null) {
        for (final part in summary.split(RegExp(r'[;,]\s*'))) {
          final headline = part
              .trim()
              .replaceFirst(
                RegExp(r'^(?:and|also)\s+', caseSensitive: false),
                '',
              )
              .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
          if (headline.isEmpty) {
            continue;
          }
          rows.add({
            ...common,
            'segment_type': 'News',
            'segment_title': headline,
            'news_start_time': time,
            'news_raw': summary.trim(),
            'headline_split_method': 'comma/semicolon heuristic',
            'needs_review': true,
          });
        }
      } else if (time != null) {
        rows.add({
          ...common,
          'segment_type': 'News',
          'start_time': time,
          'needs_review': true,
        });
      }
      final discussions = RegExp(
        r'^(Main discussion[^:\n]*):\s*(\d{1,2}:\d{2}(?::\d{2})?)\b',
        multiLine: true,
        caseSensitive: false,
      ).allMatches(description).toList();
      if (number != null && discussions.isNotEmpty) {
        for (final match in discussions) {
          rows.add({
            ...common,
            'segment_type': 'Main Discussion',
            'segment_title': common['episode_title'],
            'segment_label': match.group(1),
            'start_time': match.group(2),
          });
        }
      } else {
        rows.add({
          ...common,
          'segment_type': number == null ? 'Episode' : 'Main Discussion',
          'segment_title': common['episode_title'],
        });
      }
      fresh[guid] = rows;
    }
    final result = jsonEncode({
      'podcast': {
        'title': _text(channel, 'title') ?? current.podcast.title,
        'rss': feed.toString(),
      },
      'segments': [
        ...fresh.values.expand((rows) => rows),
        ...current.segments.where((s) => !fresh.containsKey(s.guid)).map(_row),
      ],
    });
    if (utf8.encode(result).length > catalogueByteLimit) {
      throw const FormatException('Updated catalogue exceeds 5 MiB.');
    }
    return result;
  }
}

String? _text(XmlElement element, String name) {
  final value = element.getElement(name)?.innerText.trim();
  return value == null || value.isEmpty ? null : value;
}

String _description(String source) {
  final buffer = StringBuffer();
  void visit(html.Node node) {
    if (node is html.Text) {
      buffer.write(node.data);
    }
    if (node is html.Element &&
        {'p', 'div', 'br', 'li'}.contains(node.localName)) {
      buffer.writeln();
    }
    for (final child in node.nodes) {
      visit(child);
    }
    if (node is html.Element && {'p', 'div', 'li'}.contains(node.localName)) {
      buffer.writeln();
    }
  }

  visit(html_parser.parseFragment(source));
  return buffer
      .toString()
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .join('\n');
}

String? _date(String? source) {
  if (source == null) {
    return null;
  }
  var value = source;
  var offset = Duration.zero;
  final zone = RegExp(r' ([+-])(\d{2})(\d{2})$').firstMatch(value);
  if (zone != null) {
    final hours = int.parse(zone.group(2)!);
    final minutes = int.parse(zone.group(3)!);
    if (hours > 23 || minutes > 59) {
      throw const FormatException('Invalid RSS timezone.');
    }
    offset = Duration(
      minutes: (hours * 60 + minutes) * (zone.group(1) == '+' ? 1 : -1),
    );
    value = '${value.substring(0, zone.start)} GMT';
  }
  return parseHttpDate(value)
      .subtract(offset)
      .toUtc()
      .toIso8601String()
      .replaceFirst('.000Z', 'Z');
}

String? _time(Duration? value) {
  if (value == null) {
    return null;
  }
  final seconds = value.inSeconds;
  return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Map<String, Object?> _row(Segment s) => {
  'guid': s.guid,
  'episode_number': s.episodeNumber,
  'episode_title': s.episodeTitle,
  'episode_published_at': s.publishedAt?.toUtc().toIso8601String().replaceFirst(
    '.000Z',
    'Z',
  ),
  'source_url': s.sourceUrl,
  'audio_url': s.audioUrl,
  'segment_type': s.type,
  'segment_title': s.title,
  'segment_label': s.label,
  'start_time': _time(s.startTime),
  'news_start_time': _time(s.newsStartTime),
  'news_raw': s.newsRaw,
  'needs_review': s.needsReview,
  'headline_split_method': s.headlineSplitMethod,
};
