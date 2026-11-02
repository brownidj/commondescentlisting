import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum PlaybackOutput { audioPlayer, applePodcasts }

abstract interface class PlaybackPreferenceStore {
  Future<PlaybackOutput?> read();
  Future<void> save(PlaybackOutput output);
}

class FilePlaybackPreferenceStore implements PlaybackPreferenceStore {
  FilePlaybackPreferenceStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File('${(await _directory()).path}/settings/playback.json');

  @override
  Future<PlaybackOutput?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    if (await file.length() > 4096) {
      throw const FormatException('Invalid preferences');
    }
    final document = jsonDecode(await file.readAsString());
    if (document is Map &&
        document['player'] == PlaybackOutput.audioPlayer.name) {
      return PlaybackOutput.audioPlayer;
    }
    if (document is Map &&
        document['player'] == PlaybackOutput.applePodcasts.name) {
      return PlaybackOutput.applePodcasts;
    }
    throw const FormatException('Unknown playback preference');
  }

  @override
  Future<void> save(PlaybackOutput output) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final pending = File('${file.path}.pending');
    try {
      await pending.writeAsString(
        jsonEncode({'player': output.name}),
        flush: true,
      );
      await pending.rename(file.path);
    } finally {
      try {
        if (await pending.exists()) await pending.delete();
      } on FileSystemException catch (_) {
        // An incomplete staging file is ignored on startup.
      }
    }
  }
}
