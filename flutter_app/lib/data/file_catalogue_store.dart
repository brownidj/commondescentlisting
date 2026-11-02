import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_catalogue.dart';

typedef SupportDirectory = Future<Directory> Function();

/// macOS: a flushed same-volume staging file replaces the active snapshot.
/// Startup ignores incomplete staging files. The chosen original is never edited.
class FileCatalogueStore implements CatalogueStore {
  FileCatalogueStore({SupportDirectory? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  static final _operations = <String, Future<void>>{};
  final SupportDirectory _directory;

  Future<T> _withExclusiveLock<T>(
    File active,
    Future<T> Function() operation,
  ) async {
    final path = active.absolute.path;
    final previous = _operations[path] ?? Future<void>.value();
    final release = Completer<void>();
    final queued = release.future;
    _operations[path] = queued;
    try {
      await previous;
      final lockFile = File('${active.path}.lock');
      final lock = await lockFile.open(mode: FileMode.append);
      var locked = false;
      try {
        await lock.lock(FileLock.blockingExclusive);
        locked = true;
        return await operation();
      } finally {
        try {
          if (locked) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
    } finally {
      release.complete();
      if (identical(_operations[path], queued)) _operations.remove(path);
    }
  }

  Future<File> _active() async {
    final directory = await _directory();
    return File('${directory.path}/catalogue/active.yaml');
  }

  @override
  Future<String?> read() async {
    final file = await _active();
    if (!await file.parent.exists()) return null;
    return _withExclusiveLock(file, () async {
      if (!await file.exists()) return null;
      if (await file.length() > catalogueByteLimit) {
        throw const FormatException(
          'The saved catalogue exceeds the 5 MiB limit.',
        );
      }
      return readCatalogueBytes(file.openRead());
    });
  }

  @override
  Future<void> save(String yaml) async {
    if (yaml.length > catalogueByteLimit) {
      throw const FormatException(
        'The YAML file exceeds the 5 MiB import limit.',
      );
    }
    final bytes = utf8.encode(yaml);
    if (bytes.length > catalogueByteLimit) {
      throw const FormatException(
        'The YAML file exceeds the 5 MiB import limit.',
      );
    }
    final active = await _active();
    await active.parent.create(recursive: true);
    await _withExclusiveLock(active, () async {
      Directory? stagingDirectory;
      try {
        final createdDirectory = await active.parent.createTemp(
          '.active.yaml-staging-',
        );
        stagingDirectory = createdDirectory;
        final staging = File('${createdDirectory.path}/active.yaml');
        await staging.writeAsBytes(bytes, flush: true);
        // Do not delete active first: a failed write/rename must retain it.
        await staging.rename(active.path);
      } finally {
        // A failure to remove our unique staging directory cannot undo a commit.
        try {
          if (stagingDirectory != null && await stagingDirectory.exists()) {
            await stagingDirectory.delete(recursive: true);
          }
        } on FileSystemException catch (_) {
          // Leftover staging directories are ignored on startup.
        }
      }
    });
  }

  @override
  Future<void> clear() async {
    final active = await _active();
    await active.parent.create(recursive: true);
    await _withExclusiveLock(active, () async {
      if (await active.exists()) await active.delete();
    });
  }
}
