import 'index_models.dart';

String normalizedIndexText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[–—‑]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

RegExp indexTermPattern(String term) => RegExp(
  '(^|[^\\p{L}\\p{N}_])${RegExp.escape(normalizedIndexText(term))}(?=\$|[^\\p{L}\\p{N}_])',
  unicode: true,
);

/// Derived postings narrow each phrase lookup to passages containing its rarest
/// word. Names and aliases do not repeatedly scan every transcript passage.
class PassageIndex {
  PassageIndex(Iterable<CurrentTranscript> documents) {
    final words = RegExp(r'[\p{L}\p{N}_]+', unicode: true);
    for (final document in documents) {
      for (final cue in document.transcript.cues) {
        final position = _occurrences.length;
        final text = normalizedIndexText(cue.text);
        _occurrences.add((document: document, cue: cue));
        _texts.add(text);
        _quotes
            .putIfAbsent('${document.episode.guid}\u0000$text', () => [])
            .add(position);
        for (final word
            in words.allMatches(text).map((m) => m.group(0)!).toSet()) {
          _postings.putIfAbsent(word, () => []).add(position);
        }
      }
    }
  }
  final _occurrences = <IndexOccurrence>[];
  final _texts = <String>[];
  final _postings = <String, List<int>>{};
  final _quotes = <String, List<int>>{};
  List<IndexOccurrence> find(IndexEntity entity) {
    if (entity.review == IndexReview.rejected) {
      return const [];
    }
    if (entity.details != null) {
      // Contextual classifications belong only to the reviewed occurrence, not
      // to every later substring/name match or a differently prepared edition.
      return [
        for (final occurrence in _occurrences)
          if (entity.anchors.any(
            (a) =>
                a.guid == occurrence.document.episode.guid &&
                a.edition == occurrence.document.edition &&
                a.passageId == occurrence.cue.id &&
                a.passageText == occurrence.cue.text &&
                occurrence.cue.text.contains(a.quote),
          ))
            occurrence,
      ];
    }
    final hits = <int>{};
    for (final term in [
      if (entity.anchors.isEmpty || !entity.name.startsWith('Untitled '))
        entity.name,
      ...entity.aliases,
    ]) {
      if (term.trim().isEmpty) {
        continue;
      }
      final words = RegExp(
        r'[\p{L}\p{N}_]+',
        unicode: true,
      ).allMatches(normalizedIndexText(term)).map((m) => m.group(0)!).toSet();
      if (words.isEmpty) {
        continue;
      }
      final lists =
          words.map((word) => _postings[word] ?? const <int>[]).toList()
            ..sort((a, b) => a.length.compareTo(b.length));
      final pattern = indexTermPattern(term);
      for (final position in lists.first) {
        if (pattern.hasMatch(_texts[position])) {
          hits.add(position);
        }
      }
    }
    for (final anchor in entity.anchors) {
      hits.addAll(
        _quotes['${anchor.guid}\u0000${normalizedIndexText(anchor.quote)}'] ??
            [],
      );
    }
    final positions = hits.toList()..sort();
    return [for (final position in positions) _occurrences[position]];
  }
}

List<IndexOccurrence> indexOccurrences(
  IndexEntity entity,
  Iterable<CurrentTranscript> documents,
) => PassageIndex(documents).find(entity);

/// Only literal evidence is proposed. Publication metadata stays unknown.
List<IndexEntity> suggestIndexEntries(Iterable<CurrentTranscript> documents) {
  final entries = <String, IndexEntity>{};
  const namePattern = r'([A-Z][a-z]+(?:[ -][A-Z][a-z]+){1,3})';
  final authorPattern = RegExp(
    '(?:research|paper|article)(?: at [A-Za-z ]+)? (?:is |was |also )?by $namePattern',
  );
  final binomial = RegExp(r'\b([A-Z][a-z]{3,} [a-z]{3,})\b');
  final placePattern = RegExp(
    r'\b(?:in|from|near|across) ([A-Z][a-z]{2,}(?:[ -][A-Z][a-z]+){0,3})',
  );
  final unitPattern = RegExp(
    r'\b([A-Z][a-z]+(?:[ -][A-Z][a-z]+){0,2} (?:Formation|Group|Supergroup|Basin))\b',
  );
  final doiPattern = RegExp(r'\b10\.\d{4,9}/[^\s<>]+');
  for (final document in documents) {
    for (final cue in document.transcript.cues) {
      final text = cue.text;
      for (final pattern in [placePattern, unitPattern]) {
        for (final match in pattern.allMatches(text)) {
          final name = match.group(1)!;
          if ([
            'The',
            'This',
            'That',
            'Our',
            'Your',
            'David',
            'Will',
          ].contains(name)) {
            continue;
          }
          final id = 'place:${name.toLowerCase()}';
          entries.putIfAbsent(
            id,
            () => IndexEntity(
              id: id,
              kind: IndexKind.place,
              name: name,
              subtype: pattern == unitPattern ? 'geological unit' : '',
              note: 'Possible place or geological unit in transcript wording. Classification and spelling need review.',
            ),
          );
        }
      }
      for (final match in authorPattern.allMatches(text)) {
        final name = match.group(1)!;
        final id = 'author:${name.toLowerCase()}';
        entries.putIfAbsent(
          id,
          () => IndexEntity(
            id: id,
            kind: IndexKind.author,
            name: name,
            note: 'Literal author wording in transcript; spelling and identity need review.',
          ),
        );
      }
      if (RegExp(
        r'\b(fossil|species|genus|named|called)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
        for (final match in binomial.allMatches(text)) {
          final name = match.group(1)!;
          if ([
            'The ',
            'This ',
            'That ',
            'There ',
            'These ',
            'Those ',
            'They ',
            'What ',
            'When ',
            'Which ',
            'Well ',
            'Some ',
            'Also ',
            'Because ',
            'Before ',
            'After ',
            'Episode ',
            'David ',
            'Will ',
          ].any(name.startsWith)) {
            continue;
          }
          final id = 'fossil:${name.toLowerCase()}';
          entries.putIfAbsent(
            id,
            () => IndexEntity(
              id: id,
              kind: IndexKind.fossil,
              name: name,
              note: 'Possible scientific name near taxonomic wording. May be a false positive; confirm before treating it as a fossil name.',
            ),
          );
        }
      }
      final paper = RegExp(
        r'\b(research by|paper by|published in|in the journal)\b',
        caseSensitive: false,
      ).hasMatch(text);
      final article = RegExp(
        r'\barticle (?:is |also )?(?:by|at|in)\b',
        caseSensitive: false,
      ).hasMatch(text);
      final dois = doiPattern
          .allMatches(text)
          .map((m) => m.group(0)!.replaceFirst(RegExp(r'[.,;]+$'), ''))
          .toList();
      for (final kind in [
        if (paper || dois.isNotEmpty) IndexKind.paper,
        if (article) IndexKind.article,
      ]) {
        final id =
            '${kind.name}:${document.episode.guid}:${document.edition}:${cue.id}';
        final attribution = RegExp(
          kind == IndexKind.paper
              ? '(?:research|paper) (?:is |was )?by $namePattern'
              : 'article(?: at [A-Za-z ]+)? (?:is |was |also )?by $namePattern',
        );
        final authorNames = attribution
            .allMatches(text)
            .map((m) => 'author:${m.group(1)!.toLowerCase()}')
            .where(entries.containsKey)
            .toList();
        entries[id] = IndexEntity(
          id: id,
          kind: kind,
          name:
              'Untitled ${kind.name} — Episode ${document.episode.number ?? "side"}, passage ${cue.id}',
          doi: dois.firstOrNull ?? '',
          authorIds: authorNames.toSet().toList(),
          anchors: [IndexAnchor(guid: document.episode.guid, quote: text)],
          note: 'Reference mentioned in transcript. Title, author attribution and publication details are unverified; check the quotation.',
        );
      }
    }
  }
  return entries.values.toList();
}
