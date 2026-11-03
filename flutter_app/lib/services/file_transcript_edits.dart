import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'transcript_edits.dart';

class FileTranscriptEditStore implements TranscriptEditStore {
  FileTranscriptEditStore({
    Future<Directory> Function()? directory,
    this.editionKey,
  }) : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  final String? editionKey;
  static const byteLimit = 20 * 1024 * 1024;
  static final Map<String, Future<void>> _writeQueues = {};

  Future<File> _file(String guid) async {
    // Encode the identity, never interpret a GUID as a filesystem path.
    final name = utf8
        .encode(guid)
        .map((v) => v.toRadixString(16).padLeft(2, '0'))
        .join();
    final edition = editionKey;
    if (edition != null && !RegExp(r'^[a-f0-9]{32}$').hasMatch(edition)) {
      throw const FormatException('Invalid transcript edition.');
    }
    final suffix = edition == null ? '' : '/editions/$edition';
    return File(
      '${(await _directory()).path}/transcript-edits$suffix/$name.json',
    );
  }

  @override
  Future<String?> read(String guid) async => _read(await _file(guid));

  Future<String?> _read(File file) async {
    if (!await file.exists()) return null;
    if (await file.length() > byteLimit) {
      throw const FormatException('Transcript history is too large.');
    }
    return file.readAsString();
  }

  @override
  Future<bool> writeIfUnchanged(
    String guid, {
    required String? expectedDocument,
    required String document,
  }) async {
    if (utf8.encode(document).length > byteLimit) {
      throw const FormatException(
        'Transcript history is too large. Export a backup.',
      );
    }
    final file = await _file(guid);
    await file.parent.create(recursive: true);
    return _serialize(file.path, () async {
      final lock = await File('${file.path}.lock').open(mode: FileMode.append);
      var locked = false;
      try {
        await lock.lock(FileLock.exclusive);
        locked = true;
        String? current;
        try {
          current = await _read(file);
        } on FormatException {
          return false;
        }
        if (current != expectedDocument) return false;

        final pending = File(
          '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.pending',
        );
        var staged = false;
        try {
          await pending.create(exclusive: true);
          staged = true;
          await pending.writeAsString(document, flush: true);
          await pending.rename(file.path);
          return true;
        } finally {
          try {
            if (staged && await pending.exists()) await pending.delete();
          } on FileSystemException catch (_) {
            // Staging leftovers are ignored; never report a successful rename
            // as a failure.
          }
        }
      } finally {
        try {
          if (locked) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
    });
  }

  Future<T> _serialize<T>(String key, Future<T> Function() action) async {
    final previous = _writeQueues[key] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _writeQueues[key] = tail;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
      if (identical(_writeQueues[key], tail)) _writeQueues.remove(key);
    }
  }
}
