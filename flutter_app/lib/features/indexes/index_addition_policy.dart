import '../catalogue/catalogue_words.dart';
import 'index_deletion_blacklist.dart';
import 'index_heading.dart';
import 'index_models.dart';
import 'index_word_forms.dart';

String? indexAdditionProblem(
  IndexEntity candidate,
  Iterable<IndexEntity> registry,
) {
  for (final name in [candidate.name, ...candidate.aliases]) {
    if (isFunctionOnlyPhrase(name)) {
      return 'Prepositions, articles and other standalone grammatical words '
          'cannot be added to the index. Enter a meaningful name or subject.';
    }
  }
  final deleted = registry.where((entry) => entry.deleted).toList();
  final blacklist = IndexDeletionBlacklist(deleted);
  for (final name in [candidate.name, ...candidate.aliases]) {
    for (final kind in IndexKind.values) {
      final probe = IndexEntity(
        id: candidate.id,
        kind: kind,
        name: name,
        variantIds: candidate.variantIds,
      );
      if (blacklist.blocks(probe)) {
        return '“$name” is on the saved deletion list and cannot be added '
            'again, including under a different category.';
      }
    }
    // Apply existing article, descriptive filing and common-name plural rules.
    for (final entry in deleted) {
      for (final oldName in [entry.name, ...entry.aliases]) {
        final old = IndexEntity(
          id: 'deleted-form',
          kind: entry.kind,
          name: oldName,
          subtype: entry.subtype,
        );
        final next = IndexEntity(
          id: 'proposed-form',
          kind: entry.kind,
          name: name,
          subtype: entry.subtype,
        );
        if (indexBlacklistKey(
                  indexHeading(oldName, category: entry.kind.name),
                ) ==
                indexBlacklistKey(
                  indexHeading(name, category: entry.kind.name),
                ) ||
            mergeIndexWordForms([old, next]).length == 1) {
          return '“$name” matches an entry on the saved deletion list and '
              'cannot be added again.';
        }
      }
    }
  }
  return null;
}
