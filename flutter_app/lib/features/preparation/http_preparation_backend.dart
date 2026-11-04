import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/local_prepared_episodes.dart';
import 'preparation_backend.dart';
import 'preparation_models.dart';

class HttpPreparationBackend implements PreparationBackend {
  HttpPreparationBackend({HttpClient? client, this.settingsFile})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 3);
  }

  final HttpClient _client;
  final Future<File> Function()? settingsFile;
  Uri? _base;
  String? _token;

  Future<File> _settings() async {
    final loader = settingsFile;
    if (loader != null) return loader();
    return File(
      '${(await getApplicationSupportDirectory()).path}/preparation-connection.json',
    );
  }

  void _setConnection(Map<String, dynamic> value) {
    final uri = Uri.parse(value['url'] as String);
    final token = value['token'] as String;
    if (uri.scheme != 'http' ||
        !{'127.0.0.1', 'localhost'}.contains(uri.host) ||
        uri.port != 8765 ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{'', '/'}.contains(uri.path) ||
        !RegExp(r'^[A-Za-z0-9_-]{32,}$').hasMatch(token)) {
      throw const FormatException('Invalid local worker connection.');
    }
    _base = uri;
    _token = token;
  }

  @override
  Future<void> configure() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Connect to project',
    );
    if (folder == null) throw StateError('Project selection cancelled.');
    final file = File('$folder/work/episode-preparation/connection.json');
    if (!await file.exists()) {
      throw StateError(
        'Start scripts/episode_preparation_server.zsh in this project first.',
      );
    }
    if (await file.length() > 4096) {
      throw const FormatException('Invalid worker connection file.');
    }
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    _setConnection(data);
    await _request('GET', '/health');
    final settings = await _settings();
    await settings.parent.create(recursive: true);
    final pending = File('${settings.path}.pending');
    await pending.writeAsString(jsonEncode(data), flush: true);
    await pending.rename(settings.path);
  }

  @override
  Future<void> connect() async {
    if (_base == null) {
      final file = await _settings();
      if (!await file.exists()) {
        throw StateError(
          'Choose the project folder to connect to the preparation worker.',
        );
      }
      _setConnection(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    }
    await _request('GET', '/health');
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _base;
    if (base == null) throw StateError('Preparation worker is not connected.');
    return base.replace(path: path, queryParameters: query);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final request = await _client
        .openUrl(method, _uri(path, query))
        .timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    if (body != null) {
      final payload = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = payload.length;
      request.add(payload);
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final part in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(part);
      if (bytes.length > 20 * 1024 * 1024) {
        throw const FormatException('Worker response exceeds 20 MiB.');
      }
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (response.statusCode >= 400) {
      throw StateError(
        result is Map ? '${result['error']}' : 'Worker request failed.',
      );
    }
    return result;
  }

  @override
  Future<List<PreparationModel>> models() async =>
      (await _request('GET', '/models') as List)
          .map(
            (value) => PreparationModel.fromJson(value as Map<String, dynamic>),
          )
          .toList();
  @override
  Future<PreparationEpisode> inspect(String guid) async =>
      PreparationEpisode.fromJson(
        await _request('GET', '/episode', query: {'guid': guid})
            as Map<String, dynamic>,
      );
  @override
  Future<PreparationJob?> currentJob() async {
    final value = await _request('GET', '/jobs/current');
    return value == null
        ? null
        : PreparationJob.fromJson(value as Map<String, dynamic>);
  }

  @override
  Future<PreparationJob> start({
    required String guid,
    required String model,
    required bool replace,
    required bool redownload,
    bool refineChatGPT = false,
  }) async => PreparationJob.fromJson(
    await _request(
      'POST',
      '/jobs',
      body: {
        'guid': guid,
        'model': model,
        'replace': replace,
        'redownload': redownload,
        'refine_chatgpt': refineChatGPT,
      },
    ) as Map<String, dynamic>,
  );
  @override
  Future<PreparationJob> job(String id) async => PreparationJob.fromJson(
    await _request('GET', '/jobs/$id') as Map<String, dynamic>,
  );
  @override
  Future<void> cancel(String id) async {
    await _request('POST', '/jobs/$id/cancel', body: {});
  }

  @override
  Future<void> refreshLibrary() async {
    final rows = await _request('GET', '/library') as List;
    final editions = <LocalPreparedEdition>[];
    for (final value in rows) {
      final row = value as Map<String, dynamic>;
      final key = row['key'] as String;
      final edition = row['edition'] as String;
      final identity = row['audio_identity'] as String;
      final duration = row['duration_ms'] as int;
      final count = row['passage_count'] as int;
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key) ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(edition) ||
          !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(identity) ||
          duration <= 0 ||
          count <= 0) {
        throw const FormatException('Invalid local episode descriptor.');
      }
      final prefix = '/media/$key/$edition/';
      final query = {'token': _token!};
      editions.add(
        LocalPreparedEdition(
          guid: row['guid'] as String,
          hasIndex: row['has_index'] == true,
          edition: edition,
          audioUri: _uri('${prefix}audio.opus', query),
          audioIdentity: identity,
          duration: Duration(milliseconds: duration),
          passageCount: count,
          loadText: (file) async =>
              jsonEncode(await _request('GET', '$prefix$file', query: query)),
        ),
      );
    }
    LocalPreparedEpisodes.replace(editions);
  }

  @override
  void dispose() => _client.close(force: true);
}
