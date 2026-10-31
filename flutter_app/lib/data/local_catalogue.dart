import 'dart:convert';
import 'dart:typed_data';

import 'catalogue_repository.dart';

const catalogueByteLimit = 5 * 1024 * 1024;

/// Bounds streamed reads too, in case a file grows after the initial size check.
Future<String> readCatalogueBytes(
  Stream<List<int>> chunks, {
  int limit = catalogueByteLimit,
}) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException(
        'The YAML file exceeds the 5 MiB import limit.',
      );
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

class LocalCatalogueSource implements CatalogueSource {
  LocalCatalogueSource(this.contents, {this.name = 'Imported YAML'});
  final String contents;
  @override
  final String name;
  @override
  Future<String> load() async => contents;
}

abstract interface class CatalogueStore {
  Future<String?> read();
  Future<void> save(String yaml);
  Future<void> clear();
}
