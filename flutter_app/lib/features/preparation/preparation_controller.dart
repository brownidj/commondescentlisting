import 'dart:async';

import 'package:flutter/foundation.dart';

import 'preparation_backend.dart';
import 'preparation_models.dart';

class PreparationController extends ChangeNotifier {
  PreparationController(this.backend);
  final PreparationBackend backend;
  PreparationJob? job;
  bool connected = false;
  bool connecting = false;
  String? error;
  int libraryRevision = 0;
  Timer? _poll;
  bool _disposed = false;
  bool _polling = false;
  bool _starting = false;

  bool get busy => _starting || job?.active == true;

  Future<bool> connect({bool configure = false}) async {
    if (connecting) return false;
    connecting = true;
    error = null;
    notifyListeners();
    try {
      if (configure) await backend.configure();
      await backend.connect();
      await backend.refreshLibrary();
      job = await backend.currentJob();
      if (_disposed) return false;
      connected = true;
      libraryRevision++;
      if (job?.active == true) _watch();
      return true;
    } catch (exception) {
      if (!_disposed) {
        connected = false;
        error = '$exception';
      }
      return false;
    } finally {
      if (!_disposed) {
        connecting = false;
        notifyListeners();
      }
    }
  }

  Future<void> prepare({
    required String guid,
    required String model,
    required bool replace,
    required bool redownload,
    bool refineChatGPT = false,
    bool enrichmentOnly = false,
    bool refinementOnly = false,
    String? retryJob,
  }) async {
    if (busy) throw StateError('An episode is already being prepared.');
    _starting = true;
    error = null;
    notifyListeners();
    try {
      job = await backend.start(
        guid: guid,
        model: model,
        replace: replace,
        redownload: redownload,
        refineChatGPT: refineChatGPT,
        enrichmentOnly: enrichmentOnly,
        refinementOnly: refinementOnly,
        retryJob: retryJob,
      );
      if (!_disposed) _watch();
    } catch (exception) {
      if (!_disposed) error = '$exception';
      rethrow;
    } finally {
      if (!_disposed) {
        _starting = false;
        notifyListeners();
      }
    }
  }

  Future<void> resumePreparation() async {
    final previous = job;
    if (previous == null || previous.active || !previous.canResume) return;
    await prepare(
      guid: previous.guid,
      model: previous.model ?? 'medium.en',
      replace: false,
      redownload: false,
      refineChatGPT: previous.refineChatGPT,
      retryJob: previous.id,
    );
  }

  Future<void> retryEnrichment() async {
    final previous = job;
    if (previous == null || previous.active) return;
    await prepare(
      guid: previous.guid,
      model: previous.model ?? 'medium.en',
      replace: false,
      redownload: false,
      enrichmentOnly: true,
      retryJob: previous.id,
    );
  }

  Future<void> retryRefinement() async {
    final previous = job;
    if (previous == null || previous.active) return;
    await prepare(
      guid: previous.guid,
      model: previous.model ?? 'medium.en',
      replace: false,
      redownload: false,
      refineChatGPT: true,
      refinementOnly: true,
      retryJob: previous.id,
    );
  }

  void _watch() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  Future<void> _update({bool discover = false}) async {
    if (_polling || _disposed || (!discover && job == null)) return;
    _polling = true;
    try {
      final next = discover
          ? await backend.currentJob()
          : await backend.job(job!.id);
      if (_disposed) return;
      if (next == null) return;
      job = next;
      if (discover && next.active) _watch();
      error = null;
      if (!next.active) {
        if (next.state == 'completed') {
          await backend.refreshLibrary();
          if (_disposed) return;
          libraryRevision++;
        }
        _poll?.cancel();
      }
    } catch (exception) {
      if (!_disposed) {
        error =
            'Connection interrupted; the job may still be running. $exception';
      }
    } finally {
      _polling = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Discover jobs resumed or started by another client, even after local polling stopped.
  Future<void> refreshStatus() async {
    if (_disposed) return;
    if (!connected) {
      await connect();
      return;
    }
    await _update(discover: true);
  }

  Future<void> cancel() async {
    if (job?.active != true) return;
    try {
      await backend.cancel(job!.id);
    } catch (exception) {
      if (!_disposed) error = '$exception';
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    backend.dispose();
    super.dispose();
  }
}
