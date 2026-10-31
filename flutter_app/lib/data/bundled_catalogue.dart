import 'package:flutter/services.dart';

import 'catalogue_repository.dart';

/// Asset source; the repository owns parsing, validation, and grouping.
class BundledCatalogue implements CatalogueSource {
  static const assetPath = 'assets/data/segments.yaml';

  @override
  String get name => assetPath;

  @override
  Future<String> load() async {
    final source = await rootBundle.loadString(assetPath);
    if (source.trim().isEmpty) {
      throw const FormatException('The bundled catalogue is empty.');
    }
    return source;
  }
}
