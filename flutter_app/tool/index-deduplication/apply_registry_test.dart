// One-shot authorised data migration, not part of the application test suite.
// Kept inside the Flutter package for package import resolution.
// Run explicitly from flutter_app; this writes to the saved macOS registry.
import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_store.dart';
import 'package:common_descent_listing/features/indexes/index_word_forms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('apply authorised duplicate merge to current registry with CAS', () async {
    final directory = Directory(
      '/Users/david/Library/Containers/com.example.commonDescentListing/Data/Library/Application Support/com.example.commonDescentListing',
    );
    final store = FileIndexRegistryStore(directory: () async => directory);
    final original = (await store.read())!;
    final before = IndexEntity.decode(original);
    final merged = mergeIndexWordForms(before);
    for (final entry in before) {
      final result = merged.singleWhere(
        (e) => e.id == entry.id || e.variantIds.contains(entry.id),
      );
      final retained = result.anchors.map((a) => jsonEncode(a.toJson())).toSet();
      expect(
        entry.anchors.every((a) => retained.contains(jsonEncode(a.toJson()))),
        isTrue,
      );
      if (entry.review == IndexReview.confirmed) {
        expect(result.review, IndexReview.confirmed);
      }
    }
    final arachnids = merged
        .where(
          (e) =>
              e.kind == IndexKind.fossil &&
              e.name.trim().toLowerCase() == 'arachnids' &&
              e.review != IndexReview.rejected,
        )
        .toList();
    expect(arachnids, hasLength(1));
    expect(
      mergeIndexWordForms(merged).map((e) => e.toJson()).toList(),
      merged.map((e) => e.toJson()).toList(),
    );
    final out = Directory('../outputs/index-deduplication');
    await out.create(recursive: true);
    final backup = File('${out.path}/registry-before.json');
    if (await backup.exists()) {
      throw StateError('Backup already exists; refusing a repeat migration.');
    }
    await backup.writeAsString(original, flush: true);
    expect(
      await store.save(IndexEntity.encode(merged), expected: original),
      isTrue,
    );
    final report = {
      'before_entries': before.length,
      'after_entries': merged.length,
      'absorbed_entries': before.length - merged.length,
      'arachnids_headings': arachnids.length,
      'arachnids_anchors': arachnids.single.anchors.length,
      'preserved_all_evidence': true,
      'idempotent': true,
      'new_api_calls': 0,
    };
    await File('${out.path}/APPLIED.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    stdout.writeln(report);
  });
}
