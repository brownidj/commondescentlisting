import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/features/preparation/http_preparation_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// Route the fixed worker authority to an ephemeral receiver for this test.
class LoopbackClient implements HttpClient {
  LoopbackClient(this.port);
  final int port;
  final HttpClient inner = HttpClient();
  @override
  set connectionTimeout(Duration? value) => inner.connectionTimeout = value;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri uri) =>
      inner.openUrl(method, uri.replace(port: port));
  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'job and cancellation POSTs declare the exact UTF-8 byte length',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final directory = await Directory.systemTemp.createTemp('worker-request');
      final settings = File('${directory.path}/connection.json');
      await settings.writeAsString(
        jsonEncode({'url': 'http://127.0.0.1:8765', 'token': 'a' * 43}),
      );
      final requests =
          <({String path, int declared, List<int> bytes, String? transfer})>[];
      final subscription = server.listen((request) async {
        final bytes = await request.fold<List<int>>(
          [],
          (all, part) => all..addAll(part),
        );
        if (request.method == 'POST') {
          requests.add((
            path: request.uri.path,
            declared: request.contentLength,
            bytes: bytes,
            transfer: request.headers.value(HttpHeaders.transferEncodingHeader),
          ));
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path == '/jobs'
                ? {
                    'id': 'job',
                    'guid': 'guid-Élasmosaurus',
                    'state': 'running',
                    'stage': 'Starting',
                    'elapsed_seconds': 0,
                    'remaining_seconds': 60,
                    'fraction': null,
                    'error': null,
                  }
                : {'ok': true},
          ),
        );
        await request.response.close();
      });
      final backend = HttpPreparationBackend(
        client: LoopbackClient(server.port),
        settingsFile: () async => settings,
      );
      try {
        await backend.connect();
        await backend.start(
          guid: 'guid-Élasmosaurus',
          model: 'medium.en',
          replace: false,
          redownload: false,
        );
        await backend.cancel('job');
        expect(requests, hasLength(2));
        for (final request in requests) {
          expect(request.declared, request.bytes.length);
          expect(request.declared, inInclusiveRange(1, 16384));
          expect(request.transfer, isNull);
        }
        final job = requests.first;
        expect(jsonDecode(utf8.decode(job.bytes))['guid'], 'guid-Élasmosaurus');
        expect(job.declared, greaterThan(utf8.decode(job.bytes).length));
        expect(jsonDecode(utf8.decode(requests.last.bytes)), isEmpty);
        expect(requests.last.declared, 2);
      } finally {
        backend.dispose();
        await subscription.cancel();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
