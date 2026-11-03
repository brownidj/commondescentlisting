import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'playback_controller.dart';
import 'playback_audio_source.dart';

class NativeAudioEngine extends AudioEngine {
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _error;
  bool _disposed = false;

  NativeAudioEngine() {
    _subscriptions.addAll([
      _player.playerStateStream.listen((_) => _changed()),
      _player
          .createPositionStream(
            minPeriod: const Duration(milliseconds: 100),
            maxPeriod: const Duration(milliseconds: 100),
          )
          .listen((_) => _changed()),
      _player.durationStream.listen((_) => _changed()),
      _player.errorStream.listen((_) => _failed()),
    ]);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _failed() {
    _error = 'Audio playback failed. Check your connection and retry.';
    _changed();
  }

  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;
  @override
  bool get playing => _error == null && _player.playing && !completed;
  @override
  bool get completed => _player.processingState == ProcessingState.completed;
  @override
  bool get buffering =>
      _player.processingState == ProcessingState.loading ||
      _player.processingState == ProcessingState.buffering;
  @override
  String? get error => _error;

  @override
  Future<void> load(Uri uri, Duration position) async {
    _error = null;
    await _player.setAudioSource(
      playbackAudioSource(uri),
      initialPosition: position,
    );
  }

  @override
  void play() {
    // just_audio's play Future completes when playback ends, not when it starts.
    unawaited(_player.play().catchError((Object _) => _failed()));
  }

  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> stop() => _player.stop();

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
