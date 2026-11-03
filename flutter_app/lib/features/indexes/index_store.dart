import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract interface class IndexRegistryStore {
  Future<String?> read();
  Future<bool> save(String document, {required String? expected});
}

class FileIndexRegistryStore implements IndexRegistryStore {
  FileIndexRegistryStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  static Future<void> _queue = Future.value();
  static const byteLimit = 20 * 1024 * 1024;
  Future<File> _file() async =>
      File('${(await _directory()).path}/indexes/registry.json');
  Future<String?> _read(File file) async {
    if (!await file.exists()) {
      return null;
    }
    if (await file.length() > byteLimit) {
      throw const FormatException('Index registry exceeds 20 MiB.');
    }
    return file.readAsString();
  }

  @override
  Future<String?> read() async => _read(await _file());
  @override
  Future<bool> save(String document, {required String? expected}) async {
    final previous = _queue;
    final release = Completer<void>();
    _queue = release.future;
    await previous;
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final lock = await File('${file.path}.lock').open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
        if (await _read(file) != expected) {
          return false;
        }
        final pending = File(
          '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.pending',
        );
        try {
          await pending.writeAsString(document, flush: true);
          if (await pending.length() > byteLimit) {
            throw const FormatException('Index registry exceeds 20 MiB.');
          }
          await pending.rename(file.path);
        } finally {
          if (await pending.exists()) {
            await pending.delete();
          }
        }
        return true;
      } finally {
        await lock.unlock();
        await lock.close();
      }
    } finally {
      release.complete();
    }
  }
}
