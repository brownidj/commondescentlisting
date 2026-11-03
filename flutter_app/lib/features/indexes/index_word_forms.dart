import 'dart:convert';

import 'index_details.dart';
import 'index_models.dart';

String _name(String value) => value.toLowerCase().trim();

/// Compare existing common-group entries; never singularize taxonomic names or
/// invent a singular heading when only a plural entry exists.
String _plural(String singular) {
  final irregular = {'mouse': 'mice', 'goose': 'geese', 'wolf': 'wolves'};
  final words = singular.split(' ');
  final word = words.last;
  words[words.length - 1] =
      irregular[word] ??
      (RegExp(r'[^aeiou]y$').hasMatch(word)
          ? '${word.substring(0, word.length - 1)}ies'
          : RegExp(r'(s|x|z|ch|sh)$').hasMatch(word)
          ? '${word}es'
          : '${word}s');
  return words.join(' ');
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
  );
}

IndexEntity _merge(IndexEntity a, IndexEntity b) => IndexEntity(
  id: a.id,
  kind: a.kind,
  name: a.name,
  review: a.review,
  aliases: {...a.aliases, b.name, ...b.aliases},
  subtype: a.subtype,
  year: a.year,
  publication: a.publication,
  doi: a.doi,
  url: a.url,
  linkVerified: a.linkVerified,
  authorIds: a.authorIds,
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
    if (canonical == null ||
        canonical.kind != IndexKind.fossil ||
        canonical.subtype != 'organism_group') {
      continue;
    }
    for (final variantId in canonical.variantIds.toList()) {
      final variant = entries[variantId];
      if (variant == null ||
          variant.id == canonical!.id ||
          variant.kind != canonical.kind ||
          variant.subtype != canonical.subtype) {
        continue;
      }
      canonical = _merge(canonical, variant);
      entries[id] = canonical;
      entries.remove(variantId);
    }
  }
  final groups = <String, List<String>>{};
  for (final e in entries.values) {
    if (e.kind == IndexKind.fossil &&
        e.subtype == 'organism_group' &&
        RegExp(r'^[a-z][a-z -]*$').hasMatch(_name(e.name))) {
      groups.putIfAbsent(_name(e.name), () => []).add(e.id);
    }
  }
  for (final singular in groups.keys) {
    final plural = _plural(singular);
    // Ambiguous duplicate headings need explicit review rather than guessing.
    if (groups[singular]!.length != 1 || groups[plural]?.length != 1) {
      continue;
    }
    final a = entries[groups[singular]!.single];
    final b = entries[groups[plural]!.single];
    if (a == null ||
        b == null ||
        (a.review != b.review && !a.variantIds.contains(b.id))) {
      continue;
    }
    entries[a.id] = _merge(a, b);
    entries.remove(b.id);
  }
  return entries.values.toList();
}
