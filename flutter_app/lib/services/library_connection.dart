import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/local_prepared_episodes.dart';
import '../data/catalogue_repository.dart';
import '../data/local_catalogue.dart';

/// Read-only library transport, independent of the loopback preparation worker.
class LibraryConnection {
  static final instance = LibraryConnection();
  String? address;
  String? error;
  String _token = '';
  Future<File> _settings() async => File(
    '${(await getApplicationSupportDirectory()).path}/settings/library-server.json',
  );
  static Uri validateAddress(String value) {
    final uri = Uri.parse(value.trim());
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{'', '/'}.contains(uri.path)) {
      throw const FormatException(
        'Enter a server address such as http://library-mac.local:8766',
      );
    }
    return uri;
  }

  Future<String> _read(Uri uri, String token) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        throw StateError('Library request failed (${response.statusCode}).');
      }
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(part);
        if (bytes.length > 20 * 1024 * 1024) {
          throw const FormatException('Library metadata exceeds 20 MiB.');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> connect(
    String value,
    String token, {
    bool persist = true,
  }) async {
    final base = validateAddress(value);
    if (!RegExp(r'^[A-Za-z0-9_-]{32,}$').hasMatch(token)) {
      throw const FormatException('Enter the server’s read token.');
    }
    final doc = jsonDecode(
      await _read(base.resolve('/library'), token),
    ) as Map<String, dynamic>;
    if (doc['schema_version'] != 1) {
      throw const FormatException('Unsupported library version.');
    }
    Uri fileUri(String relative, {bool audio = false}) {
      if (!RegExp(
        r'^(episodes/[a-f0-9]{24}/[a-f0-9]{24}/(audio\.opus|transcript/(baseline|alignment)\.json|index-[a-f0-9]{24}\.json)|catalogues/[a-f0-9]{64}\.yaml)$',
      ).hasMatch(relative)) {
        throw const FormatException('Invalid library file path.');
      }
      final uri = base.resolve('/files/$relative');
      return audio ? uri.replace(queryParameters: {'token': token}) : uri;
    }

    final catalogue = await _read(fileUri(doc['catalogue'] as String), token);
    await CatalogueRepository(
      source: LocalCatalogueSource(catalogue, name: 'Library server'),
    ).load();
    final editions = <LocalPreparedEdition>[];
    final guids = <String>{};
    for (final item in doc['episodes'] as List) {
      final row = item as Map<String, dynamic>;
      final guid = row['guid'] as String;
      final edition = row['edition'] as String;
      final identity = row['audio_identity'] as String;
      final files = Map<String, dynamic>.from(row['files'] as Map);
      if (!guids.add(guid) ||
          edition.isEmpty ||
          !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(identity) ||
          (row['duration_ms'] as int) <= 0 ||
          (row['passage_count'] as int) <= 0) {
        throw const FormatException('Invalid library edition.');
      }
      for (final name in [
        'audio.opus',
        'transcript/baseline.json',
        'transcript/alignment.json',
        'indexing/index.json',
      ]) {
        fileUri(files[name] as String);
      }
      editions.add(
        LocalPreparedEdition(
          guid: guid,
          edition: edition,
          audioUri: fileUri(files['audio.opus'] as String, audio: true),
          audioIdentity: identity,
          duration: Duration(milliseconds: row['duration_ms'] as int),
          passageCount: row['passage_count'] as int,
          hasIndex: true,
          readOnly: true,
          loadText: (name) => _read(fileUri(files[name] as String), token),
        ),
      );
    }
    if (persist) {
      final file = await _settings();
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.pending');
      await pending.writeAsString(
        jsonEncode({'url': base.toString(), 'token': token}),
        flush: true,
      );
      await pending.rename(file.path);
    }
    address = base.toString();
    _token = token;
    error = null;
    LocalPreparedEpisodes.replaceRemote(editions);
    return catalogue;
  }

  Future<String?> restore() async {
    try {
      final file = await _settings();
      if (!await file.exists()) return null;
      if (await file.length() > 4096) {
        throw const FormatException('Invalid library settings.');
      }
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      address = validateAddress(value['url'] as String).toString();
      _token = value['token'] as String;
      return await connect(
        value['url'] as String,
        value['token'] as String,
        persist: false,
      );
    } catch (_) {
      error =
          'Saved library server is unavailable. Local data remains available.';
      return null;
    }
  }

  Future<String> refresh() => connect(address!, _token);
  Future<void> disconnect() async {
    final file = await _settings();
    if (await file.exists()) await file.delete();
    LocalPreparedEpisodes.replaceRemote([]);
    address = null;
    _token = '';
    error = null;
  }
}
