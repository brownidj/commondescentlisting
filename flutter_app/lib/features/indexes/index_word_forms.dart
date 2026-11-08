import 'dart:convert';

import 'index_details.dart';
import 'index_models.dart';

String _name(String value) =>
    value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// Compare existing common-name entries; never singularize formal taxon names or
/// invent a singular heading when only a plural entry exists.
String _plural(String singular) {
  final irregular = {
    'mouse': 'mice',
    'goose': 'geese',
    'wolf': 'wolves',
    'tooth': 'teeth',
    'foot': 'feet',
    'child': 'children',
    'person': 'people',
    'louse': 'lice',
    'leaf': 'leaves',
    'calf': 'calves',
    'life': 'lives',
  };
  final filed = singular.split(', ');
  final words = filed.first.split(' ');
  final word = words.last;
  if ({
    'species',
    'series',
    'fish',
    'sheep',
    'deer',
    'moose',
    'offspring',
  }.contains(word)) {
    return singular;
  }
  words[words.length - 1] =
      irregular[word] ??
      (RegExp(r'[^aeiou]y$').hasMatch(word)
          ? '${word.substring(0, word.length - 1)}ies'
          : RegExp(r'(s|x|z|ch|sh)$').hasMatch(word)
          ? '${word}es'
          : '${word}s');
  return [words.join(' '), ...filed.skip(1)].join(', ');
}

bool _commonName(IndexEntity e) {
  if (e.deleted || e.review == IndexReview.rejected) return false;
  final head = _name(e.heading).split(', ').first;
  if (e.kind == IndexKind.place) {
    return {
      'continent',
      'continents',
      'supercontinent',
      'supercontinents',
      'island',
      'islands',
      'mountain',
      'mountains',
      'ocean',
      'oceans',
      'river',
      'rivers',
      'lake',
      'lakes',
    }.contains(head);
  }
  if (e.kind != IndexKind.fossil) return false;
  if ({
    'genus',
    'family',
    'order',
    'class',
    'phylum',
    'taxon',
    'scientific_name',
  }.contains(e.subtype.toLowerCase())) {
    return false;
  }
  if (e.subtype.toLowerCase() == 'species') {
    // A source can label an English common name as species too.
    return RegExp(
      r'(crocodile|crocodiles|alligator|alligators|bird|birds|fish|whale|whales|shark|sharks)$',
    ).hasMatch(head);
  }
  return RegExp(r'^[a-z][a-z -]*(, [a-z -]+)?$').hasMatch(_name(e.heading));
}

List<T> _unique<T>(Iterable<T> values, String Function(T) key) {
  final seen = <String>{};
  return values.where((value) => seen.add(key(value))).toList();
}

IndexDetails? _details(IndexDetails? first, IndexDetails? second) {
  if (first == null || second == null) {
    return first ?? second;
  }
  String lines(String a, String b) => {
    ...const LineSplitter().convert(a),
    ...const LineSplitter().convert(b),
  }.where((s) => s.isNotEmpty).join('\n');
  String bibliography(String a, String b) {
    if (a.isEmpty || b.isEmpty || a == b) {
      return a.isEmpty ? b : a;
    }
    List<dynamic> rows(String text) {
      final value = jsonDecode(text);
      return value is List ? value : [value];
    }

    return const JsonEncoder.withIndent('  ')
        .convert(_unique([...rows(a), ...rows(b)], jsonEncode));
  }

  final confidence = [first.confidence, second.confidence];
  return IndexDetails(
    refinementReview: first.refinementReview.isNotEmpty
        ? first.refinementReview
        : second.refinementReview,
    spoken: {...first.spoken, ...second.spoken}.toList(),
    description: lines(first.description, second.description),
    confidence: confidence.contains('low')
        ? 'low'
        : confidence.contains('medium')
        ? 'medium'
        : first.confidence,
    normalizations: {
      ...first.normalizations,
      ...second.normalizations,
    }.toList(),
    editorialNote: lines(first.editorialNote, second.editorialNote),
    bibliography: bibliography(first.bibliography, second.bibliography),
    originalPublication: bibliography(
      first.originalPublication,
      second.originalPublication,
    ),
    sources: _unique([
      ...first.sources,
      ...second.sources,
    ], (s) => jsonEncode(s.toJson())),
    model: lines(first.model, second.model),
    externalConfirmation: first.externalConfirmation.isEmpty
        ? second.externalConfirmation
        : first.externalConfirmation,
    refinementSource: first.refinementSource.isEmpty
        ? second.refinementSource
        : first.refinementSource,
  );
}

IndexEntity _merge(IndexEntity a, IndexEntity b, {String? name}) => IndexEntity(
  id: a.id,
  kind: a.kind,
  name: name ?? a.name,
  review: a.review == IndexReview.rejected
      ? a.review
      : a.review == IndexReview.confirmed || b.review == IndexReview.confirmed
      ? IndexReview.confirmed
      : a.review,
  deleted: a.deleted,
  aliases: {
    if (name != null && name != a.name) a.name,
    ...a.aliases,
    b.name,
    ...b.aliases,
  },
  subtype: a.subtype.isEmpty ? b.subtype : a.subtype,
  year: a.year ?? b.year,
  publication: a.publication.isEmpty ? b.publication : a.publication,
  doi: a.doi.isEmpty ? b.doi : a.doi,
  url: a.url.isEmpty ? b.url : a.url,
  linkVerified: a.linkVerified || (a.url.isEmpty && b.linkVerified),
  authorIds: {...a.authorIds, ...b.authorIds},
  note: {
    ...const LineSplitter().convert(a.note),
    ...const LineSplitter().convert(b.note),
  }.where((line) => line.isNotEmpty).join('\n'),
  details: _details(a.details, b.details),
  anchors: _unique([
    ...a.anchors,
    ...b.anchors,
  ], (anchor) => jsonEncode(anchor.toJson())),
  variantIds: {...a.variantIds, b.id, ...b.variantIds},
);

List<IndexEntity> mergeIndexWordForms(Iterable<IndexEntity> source) {
  final entries = {for (final e in source) e.id: e};
  // Persisted variant membership survives a user's later heading edit/review.
  for (final id in entries.keys.toList()) {
    var canonical = entries[id];
    if (canonical == null) {
      continue;
    }
    for (final variantId in canonical.variantIds.toList()) {
      final variant = entries[variantId];
      if (variant == null ||
          variant.id == canonical!.id ||
          variant.kind != canonical.kind) {
        continue;
      }
      final singularVariant =
          _commonName(canonical) &&
          _commonName(variant) &&
          _name(canonical.heading) == _plural(_name(variant.heading));
      final plainVariant =
          _name(canonical.heading) == _name(variant.heading) &&
          _name(variant.name) == _name(variant.heading);
      canonical = _merge(
        canonical,
        variant,
        name: singularVariant || plainVariant ? variant.name : null,
      );
      entries[id] = canonical;
      entries.remove(variantId);
    }
  }
  // Local, API and renamed suggestions may share a heading despite different
  // extraction IDs or subtypes. Persist membership before plural grouping.
  final headings = <String, List<IndexEntity>>{};
  for (final entry in entries.values) {
    headings
        .putIfAbsent('${entry.kind.name}:${_name(entry.heading)}', () => [])
        .add(entry);
  }
  bool compatible(IndexEntity a, IndexEntity b) {
    // Keep every deletion record under its original durable ID.
    if (a.deleted || b.deleted) {
      return false;
    }
    if ((a.review == IndexReview.rejected) !=
        (b.review == IndexReview.rejected)) {
      return false;
    }
    if (a.kind != IndexKind.paper && a.kind != IndexKind.article) {
      return true;
    }
    bool conflict(String x, String y) =>
        x.isNotEmpty && y.isNotEmpty && _name(x) != _name(y);
    return !(a.year != null && b.year != null && a.year != b.year) &&
        !conflict(a.doi, b.doi) &&
        !conflict(a.publication, b.publication) &&
        !conflict(a.url, b.url);
  }

  for (final group in headings.values) {
    group.sort((a, b) {
      int priority(IndexEntity e) =>
          (e.review == IndexReview.confirmed ? 4 : 0) +
          (e.id.startsWith('manual:') ? 2 : 0) +
          (e.variantIds.isNotEmpty ? 1 : 0);
      // Prefer the plain source heading when an article-free spelling exists.
      final aPlain = _name(a.name) == _name(a.heading);
      final bPlain = _name(b.name) == _name(b.heading);
      final plain = (bPlain ? 1 : 0).compareTo(aPlain ? 1 : 0);
      if (plain != 0) return plain;
      final order = priority(b).compareTo(priority(a));
      return order == 0 ? a.id.compareTo(b.id) : order;
    });
    final canonicalIds = <String>[];
    for (final entry in group) {
      final matches = canonicalIds.where(
        (id) => compatible(entries[id]!, entry),
      );
      if (matches.isEmpty) {
        canonicalIds.add(entry.id);
      } else {
        final id = matches.first;
        entries[id] = _merge(entries[id]!, entry);
        entries.remove(entry.id);
      }
    }
  }
  final groups = <String, List<String>>{};
  for (final e in entries.values.where(_commonName)) {
    groups
        .putIfAbsent('${e.kind.name}:${_name(e.heading)}', () => [])
        .add(e.id);
  }
  for (final key in groups.keys) {
    final split = key.indexOf(':');
    final singular = key.substring(split + 1);
    final plural = _plural(singular);
    if (plural == singular) continue;
    final pluralKey = '${key.substring(0, split)}:$plural';
    if (groups[key]!.length != 1 || groups[pluralKey]?.length != 1) continue;
    final a = entries[groups[key]!.single];
    final b = entries[groups[pluralKey]!.single];
    if (a == null || b == null || !compatible(a, b)) continue;
    entries[a.id] = _merge(a, b);
    entries.remove(b.id);
  }
  final canonicalIds = <String, String>{
    for (final entry in entries.values)
      for (final id in entry.variantIds) id: entry.id,
  };
  return IndexEntity.decode(
    jsonEncode({
      'schema_version': 1,
      'entries': [
        for (final entry in entries.values)
          {
            ...entry.toJson(),
            'author_ids': entry.authorIds
                .map((id) => canonicalIds[id] ?? id)
                .toSet()
                .toList(),
          },
      ],
    }),
  );
}
