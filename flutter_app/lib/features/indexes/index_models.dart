import 'dart:convert';

import '../../models/episode_transcript.dart';
import '../../services/current_transcript.dart';
import 'index_details.dart';
import 'index_extraction.dart';

export '../../services/current_transcript.dart' show CurrentTranscript;

enum IndexKind {
  fossil('Taxonomy'),
  place('Places'),
  paper('Papers'),
  article('Articles'),
  author('Authors');

  const IndexKind(this.label);
  final String label;
}

enum IndexReview { suggested, confirmed, rejected }

class IndexAnchor {
  const IndexAnchor({
    required this.guid,
    required this.quote,
    this.passageId,
    this.edition,
    this.passageText,
    this.extraction = const [],
  });
  final String guid;
  final String quote;
  final int? passageId;
  final String? edition;
  final String? passageText;
  final List<IndexExtraction> extraction;
  Map<String, dynamic> toJson() => {
    'guid': guid,
    'quote': quote,
    if (passageId != null) 'passage_id': passageId,
    if (edition != null) 'edition': edition,
    if (passageText != null) 'passage_text': passageText,
    if (extraction.isNotEmpty)
      'extraction': extraction.map((e) => e.toJson()).toList(),
  };
}

class IndexEntity {
  IndexEntity({
    required this.id,
    required this.kind,
    required this.name,
    this.review = IndexReview.suggested,
    this.deleted = false,
    Iterable<String> aliases = const [],
    this.subtype = '',
    this.year,
    this.publication = '',
    this.doi = '',
    this.url = '',
    this.linkVerified = false,
    Iterable<String> authorIds = const [],
    Iterable<IndexAnchor> anchors = const [],
    this.note = '',
    this.details,
    Iterable<String> variantIds = const [],
  }) : aliases = List.unmodifiable(aliases),
       authorIds = List.unmodifiable(authorIds),
       anchors = List.unmodifiable(anchors),
       variantIds = List.unmodifiable(variantIds);
  final String id;
  final IndexKind kind;
  final String name;
  final IndexReview review;
  final bool deleted;
  final List<String> aliases;
  final String subtype;
  final int? year;
  final String publication;
  final String doi;
  final String url;
  final bool linkVerified;
  final List<String> authorIds;
  final List<IndexAnchor> anchors;
  final String note;
  final IndexDetails? details;
  final List<String> variantIds;
  bool get isPublication =>
      kind == IndexKind.paper || kind == IndexKind.article;
  Uri? get verifiedUri => !linkVerified
      ? null
      : url.isNotEmpty
      ? Uri.parse(url)
      : doi.isEmpty
      ? null
      : Uri.https('doi.org', '/$doi');

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'review': review.name,
    if (deleted) 'deleted': true,
    'aliases': aliases,
    'subtype': subtype,
    'year': year,
    'publication': publication,
    'doi': doi,
    'url': url,
    'link_verified': linkVerified,
    'author_ids': authorIds,
    'anchors': anchors.map((a) => a.toJson()).toList(),
    'note': note,
    if (details != null) 'details': details!.toJson(),
    if (variantIds.isNotEmpty) 'variant_ids': variantIds,
  };

  static List<IndexEntity> decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map<String, dynamic> ||
        root['schema_version'] != 1 ||
        root['entries'] is! List) {
      throw const FormatException('Invalid index schema.');
    }
    final result = <IndexEntity>[];
    for (final raw in root['entries'] as List) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Invalid index entry.');
      }
      String string(String key, [String fallback = '']) {
        final value = raw[key] ?? fallback;
        if (value is! String || value.length > 20000) {
          throw FormatException('Invalid $key.');
        }
        return value;
      }

      List<String> strings(String key) {
        final value = raw[key] ?? [];
        if (value is! List ||
            value.any((v) => v is! String || v.length > 1000)) {
          throw FormatException('Invalid $key.');
        }
        return value.cast<String>();
      }

      final kind = IndexKind.values
          .where((k) => k.name == raw['kind'])
          .firstOrNull;
      final review = IndexReview.values
          .where((r) => r.name == (raw['review'] ?? 'suggested'))
          .firstOrNull;
      final id = string('id');
      final name = string('name');
      final year = raw['year'];
      final url = string('url');
      final doi = string('doi');
      final uri = Uri.tryParse(url);
      if (kind == null ||
          review == null ||
          id.trim().isEmpty ||
          id.length > 1000 ||
          name.trim().isEmpty ||
          name.length > 1000 ||
          (year != null && (year is! int || year < 1000 || year > 3000)) ||
          (raw['link_verified'] != null && raw['link_verified'] is! bool) ||
          (raw['deleted'] != null && raw['deleted'] is! bool) ||
          (url.isNotEmpty &&
              (uri == null ||
                  !['http', 'https'].contains(uri.scheme) ||
                  uri.host.isEmpty ||
                  uri.userInfo.isNotEmpty)) ||
          (doi.isNotEmpty && !RegExp(r'^10\.\d{4,9}/\S+$').hasMatch(doi))) {
        throw const FormatException('Invalid name, date, DOI or web link.');
      }
      final anchorRows = raw['anchors'] ?? [];
      if (anchorRows is! List) {
        throw const FormatException('Invalid passage anchors.');
      }
      final anchors = <IndexAnchor>[];
      for (final a in anchorRows) {
        if (a is! Map ||
            a['guid'] is! String ||
            a['quote'] is! String ||
            (a['guid'] as String).isEmpty ||
            (a['quote'] as String).trim().isEmpty ||
            (a['quote'] as String).length > 20000) {
          throw const FormatException('Invalid passage anchor.');
        }
        if ((a['passage_id'] != null ||
                a['edition'] != null ||
                a['passage_text'] != null) &&
            (a['passage_id'] is! int ||
                (a['passage_id'] as int) < 1 ||
                a['edition'] is! String ||
                (a['edition'] as String).isEmpty ||
                a['passage_text'] is! String ||
                !(a['passage_text'] as String).contains(
                  a['quote'] as String,
                ))) {
          throw const FormatException(
            'Invalid edition-bound passage evidence.',
          );
        }
        anchors.add(
          IndexAnchor(
            guid: a['guid'] as String,
            quote: a['quote'] as String,
            passageId: a['passage_id'] as int?,
            edition: a['edition'] as String?,
            passageText: a['passage_text'] as String?,
            extraction: IndexExtraction.decode(
              a['extraction'],
              a['passage_text'] as String?,
              a['quote'] as String,
            ),
          ),
        );
      }
      result.add(
        IndexEntity(
          id: id,
          kind: kind,
          name: name,
          review: review,
          deleted: raw['deleted'] == true,
          aliases: strings('aliases'),
          subtype: string('subtype'),
          year: year as int?,
          publication: string('publication'),
          doi: doi,
          url: url,
          linkVerified: raw['link_verified'] == true,
          authorIds: strings('author_ids'),
          anchors: anchors,
          note: string('note'),
          details: IndexDetails.decode(raw['details']),
          variantIds: strings('variant_ids'),
        ),
      );
    }
    final byId = {for (final e in result) e.id: e};
    if (byId.length != result.length) {
      throw const FormatException('Duplicate index IDs.');
    }
    for (final e in result) {
      if (e.authorIds.toSet().length != e.authorIds.length ||
          (e.authorIds.isNotEmpty && !e.isPublication) ||
          e.authorIds.any((id) => byId[id]?.kind != IndexKind.author)) {
        throw const FormatException(
          'Publication authors must reference unique author entries in order.',
        );
      }
    }
    return result;
  }

  static String encode(Iterable<IndexEntity> entries) =>
      const JsonEncoder.withIndent('  ').convert({
        'schema_version': 1,
        'entries': entries.map((e) => e.toJson()).toList(),
      });
}

typedef IndexOccurrence = ({CurrentTranscript document, TranscriptCue cue});
