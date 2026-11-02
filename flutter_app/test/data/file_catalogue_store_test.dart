import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/file_catalogue_store.dart';
import 'package:common_descent_listing/data/local_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

String _repeat(String value, int count) {
  final chunk = List.filled(1024, value).join();
  final buffer = StringBuffer();
  for (var written = 0; written < count; written += 1024) {
    final remaining = count - written;
    buffer.write(
      remaining >= 1024 ? chunk : List.filled(remaining, value).join(),
    );
  }
  return buffer.toString();
}

void main() {
  test(
    'bounded streams reject overflow and invalid UTF-8 without parsing',
    () async {
      expect(
        await readCatalogueBytes(Stream.value(utf8.encode('test')), limit: 4),
        'test',
      );
      await expectLater(
        readCatalogueBytes(
          Stream.fromIterable([
            [1, 2],
            [3, 4, 5],
          ]),
          limit: 4,
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        readCatalogueBytes(Stream.value([255])),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'staged replacement ignores legacy pending files and clear is durable',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'catalogue-store-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileCatalogueStore(directory: () async => directory);
      expect(await store.read(), isNull);
      await store.save('previous');
      final pending = File('${directory.path}/catalogue/active.yaml.pending');
      await pending.writeAsString('partial');
      expect(await store.read(), 'previous');
      await store.save('replacement');
      expect(await store.read(), 'replacement');
      expect(await pending.readAsString(), 'partial');
      await store.clear();
      expect(await store.read(), isNull);
    },
  );

  test(
    'save accepts the exact byte limit and rejects oversized UTF-8',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'catalogue-size-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileCatalogueStore(directory: () async => directory);
      final exactLimit = _repeat('x', catalogueByteLimit);
      await store.save(exactLimit);
      expect(await store.read(), exactLimit);

      await expectLater(
        store.save('${exactLimit}x'),
        throwsA(isA<FormatException>()),
      );
      final multibyteOverLimit = _repeat('é', catalogueByteLimit ~/ 2 + 1);
      await expectLater(
        store.save(multibyteOverLimit),
        throwsA(isA<FormatException>()),
      );
      expect(await store.read(), exactLimit);
    },
  );

  test(
    'independent store instances serialize concurrent saves and clears',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'catalogue-concurrent-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final first = FileCatalogueStore(directory: () async => directory);
      final second = FileCatalogueStore(directory: () async => directory);

      await Future.wait([first.save('first'), second.save('second')]);
      expect(await first.read(), anyOf('first', 'second'));

      await Future.wait([first.save('saved'), second.clear()]);
      expect(await first.read(), anyOf(isNull, 'saved'));
    },
  );

  test(
    'failed replacement preserves the destination and cleans staging',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'catalogue-rename-failure-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileCatalogueStore(directory: () async => directory);
      final catalogueDirectory = Directory('${directory.path}/catalogue');
      final activeDirectory = Directory(
        '${catalogueDirectory.path}/active.yaml',
      );
      await activeDirectory.create(recursive: true);
      final sentinel = File('${activeDirectory.path}/keep.txt');
      await sentinel.writeAsString('preserve');

      await expectLater(
        store.save('replacement'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await sentinel.readAsString(), 'preserve');
      final entries = await catalogueDirectory.list().toList();
      expect(
        entries.where(
          (entry) => entry.path.contains('.active.yaml-staging-'),
        ),
        isEmpty,
      );
    },
  );
}
