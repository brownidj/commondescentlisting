import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/data/file_catalogue_store.dart';
import 'package:common_descent_listing/data/local_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

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
    'staged replacement, ignored interrupted file and durable clear',
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
      expect(await pending.exists(), isFalse);
      await store.clear();
      expect(await store.read(), isNull);
    },
  );

  test(
    'failed staging write cannot replace existing active snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'catalogue-failure-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileCatalogueStore(directory: () async => directory);
      await store.save('previous');
      // A directory at the pending-file path forces a write failure reliably.
      await Directory('${directory.path}/catalogue/active.yaml.pending')
          .create();
      await expectLater(
        store.save('replacement'),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.read(), 'previous');
    },
  );
}
