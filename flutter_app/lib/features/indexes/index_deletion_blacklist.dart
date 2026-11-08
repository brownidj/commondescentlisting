import 'index_heading.dart';
import 'index_models.dart';

/// Tombstones are the durable deletion history. Match regenerated IDs by exact
/// category/heading too; never suppress a mere substring or another category.
class IndexDeletionBlacklist {
  IndexDeletionBlacklist(Iterable<IndexEntity> entries)
    : _deleted = entries.where((e) => e.deleted).toList();
  final List<IndexEntity> _deleted;

  bool blocks(IndexEntity candidate) {
    final ids = {candidate.id, ...candidate.variantIds};
    final name = indexBlacklistKey(candidate.name);
    return _deleted.any(
      (e) =>
          {e.id, ...e.variantIds}.any(ids.contains) ||
          (candidate.kind == e.kind &&
              [
                e.name,
                ...e.aliases,
              ].any((alias) => indexBlacklistKey(alias) == name)),
    );
  }

  List<IndexEntity> apply(Iterable<IndexEntity> entries) => [
    for (final entry in entries)
      if (!entry.deleted && blocks(entry))
        entry.copyWith(deleted: true)
      else
        entry,
  ];
}
