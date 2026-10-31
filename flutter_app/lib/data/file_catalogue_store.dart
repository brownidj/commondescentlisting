import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_catalogue.dart';

typedef SupportDirectory = Future<Directory> Function();

/// macOS: a flushed sibling file is renamed over the active snapshot atomically.
/// Startup ignores incomplete .pending files. The chosen original is never edited.
class FileCatalogueStore implements CatalogueStore {
  FileCatalogueStore({SupportDirectory? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final SupportDirectory _directory;

  Future<File> _active() async {
    final directory = await _directory();
    return File('${directory.path}/catalogue/active.yaml');
  }

  @override
  Future<String?> read() async {
    final file = await _active();
    if (!await file.exists()) return null;
    if (await file.length() > catalogueByteLimit) {
      throw const FormatException(
        'The saved catalogue exceeds the 5 MiB limit.',
      );
    }
    return readCatalogueBytes(file.openRead());
  }

  @override
  Future<void> save(String yaml) async {
    final active = await _active();
    await active.parent.create(recursive: true);
    final pending = File('${active.path}.pending');
    try {
      await pending.writeAsString(yaml, flush: true);
      // Do not delete active first: a failed write/rename must retain it.
      await pending.rename(active.path);
    } finally {
      // Cleanup must not turn a successful commit into a reported failure.
      try {
        if (await pending.exists()) await pending.delete();
      } on FileSystemException catch (_) {
        // Leftover staging files are ignored on startup.
      }
    }
  }

  @override
  Future<void> clear() async {
    final active = await _active();
    if (await active.exists()) await active.delete();
  }
}
