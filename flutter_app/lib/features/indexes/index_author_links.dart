import 'dart:convert';

import 'index_models.dart';

/// Recategorising a former author must not leave invalid publication references.
/// Original quoted evidence and IDs stay intact; the repair is reviewable.
List<IndexEntity> reconcileIndexAuthorLinks(Iterable<IndexEntity> entries) {
  final list = entries.toList();
  final byId = {
    for (final e in list)
      if (!e.deleted) e.id: e,
  };
  final rows = <Map<String, dynamic>>[];
  for (final entry in list) {
    final row = entry.toJson();
    final removed = entry.authorIds
        .where((id) => byId[id]?.kind != IndexKind.author)
        .toList();
    if (removed.isNotEmpty) {
      row['author_ids'] = entry.authorIds
          .where((id) => !removed.contains(id))
          .toList();
      final note =
          'Review author attribution: links removed after recategorisation or deletion (${removed.map((id) => byId[id]?.name ?? id).join(', ')}).';
      row['note'] = entry.note.contains(note)
          ? entry.note
          : [entry.note, note].where((s) => s.isNotEmpty).join('\n');
    }
    rows.add(row);
  }
  return IndexEntity.decode(jsonEncode({'schema_version': 1, 'entries': rows}));
}
