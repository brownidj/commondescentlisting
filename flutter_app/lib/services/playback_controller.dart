import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/episode_audio.dart';

import '../models/catalogue.dart';
import '../models/episode_transcript.dart';
import 'playback_preferences.dart';

/// Native player boundary; controllers can be exercised without audio hardware.
abstract class AudioEngine extends ChangeNotifier {
  Duration get position;
  Duration? get duration;
  bool get playing;
  bool get buffering;
  bool get completed;
  String? get error;
  Future<void> load(Uri uri, Duration position);
  void play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
}

/// The player state before temporarily auditioning a transcript passage.
class PlaybackBookmark {
  const PlaybackBookmark._(
    this.episode,
    this.position,
    this.wasPlaying,
    this.wasLoaded,
    this.audioUri,
  );
  final Episode? episode;
  final Duration position;
  final bool wasPlaying;
  final bool wasLoaded;
  final Uri? audioUri;
}

typedef TranscriptEditAction = ({
  String guid,
  VoidCallback open,
  bool Function() available,
  bool visible,
  Future<void> Function(Duration)? nudge,
  bool Function(Duration)? canNudge,
});

class PlaybackController extends ChangeNotifier {
  PlaybackController({required this.createEngine, this.preferenceStore})
    : _preferencesReady = preferenceStore == null;

  final AudioEngine Function() createEngine;
  final PlaybackPreferenceStore? preferenceStore;
  PlaybackOutput _output = PlaybackOutput.audioPlayer;
  bool _preferencesReady;
  String? _preferencesError;

  PlaybackOutput get output => _output;
  bool get preferencesReady => _preferencesReady;
  String? get preferencesError => _preferencesError;

  Future<void> initialisePreferences() async {
    if (preferenceStore == null) return;
    try {
      final saved = await preferenceStore!.read();
      if (_disposed) return;
      _output = saved ?? PlaybackOutput.audioPlayer;
    } catch (_) {
      _preferencesError = 'Your saved player preference could not be read. Audio player is selected.';
    }
    _preferencesReady = true;
    _changed();
  }

  Future<void> setOutput(PlaybackOutput selected) {
    if (!preferencesReady || (output == selected && preferencesError == null)) {
      return Future.value();
    }
    return _command(() async {
      final previousPosition = position;
      var stopped = false;
      try {
        await _engine?.stop();
        stopped = true;
        _loaded = false;
        _pendingPosition = previousPosition;
        _source = null;
        await preferenceStore?.save(selected);
        if (_disposed) return;
        _output = selected;
        _preferencesError = null;
        if (selected == PlaybackOutput.applePodcasts) {
          _episode = null;
          _pendingPosition = Duration.zero;
        }
      } catch (_) {
        if (stopped) _pendingPosition = previousPosition;
        _preferencesError =
            'The player preference could not be changed. Please try again.';
      }
    });
  }

  AudioEngine? _engine;
  Episode? _episode;
  Uri? _source;
  bool _busy = false;
  bool _loaded = false;
  bool _disposed = false;
  Completer<void>? _commandDone;
  int _seekRevision = 0;

  /// Explicit position changes; natural progress and calibration do not increment.
  int get seekRevision => _seekRevision;
  final _transcripts = <String, ({EpisodeTranscript text, Duration offset})>{};

  Episode? get episode => _episode;
  bool get busy => _busy;

  void setTranscriptContext(EpisodeTranscript transcript, Duration offset) {
    if (_disposed) return;
    final previous = _transcripts[transcript.episodeGuid];
    if (identical(previous?.text, transcript) && previous?.offset == offset) {
      return;
    }
    _transcripts[transcript.episodeGuid] = (text: transcript, offset: offset);
    _changed();
  }

  TranscriptCue? get currentPassage {
    if (output != PlaybackOutput.audioPlayer) return null;
    final transcript = _transcripts[episode?.guid];
    if (transcript == null) return null;
    return transcript.text.cueAt(position + transcript.offset);
  }

  int? get transcriptPassageCount =>
      _transcripts[episode?.guid]?.text.cues.length;
  final _transcriptEditActions = <Object, TranscriptEditAction>{};

  TranscriptEditAction? get transcriptEditAction {
    TranscriptEditAction? visible;
    for (final action in _transcriptEditActions.values) {
      if (action.visible) visible = action;
    }
    return visible;
  }

  void registerTranscriptEdit(
    Object owner,
    String guid,
    VoidCallback open,
    bool Function() available,
    bool visible, {
    Future<void> Function(Duration)? nudge,
    bool Function(Duration)? canNudge,
  }) {
    if (_disposed) return;
    final previous = _transcriptEditActions[owner];
    if (previous?.guid == guid &&
        previous?.open == open &&
        previous?.available == available &&
        previous?.visible == visible &&
        previous?.nudge == nudge &&
        previous?.canNudge == canNudge) {
      return;
    }
    _transcriptEditActions[owner] = (
      guid: guid,
      open: open,
      available: available,
      visible: visible,
      nudge: nudge,
      canNudge: canNudge,
    );
    _changed();
  }

  void unregisterTranscriptEdit(Object owner) {
    if (_disposed) return;
    if (_transcriptEditActions.remove(owner) != null) _changed();
  }

  void refreshTranscriptEdit() => _changed();

  String? _error;
  Duration _pendingPosition = Duration.zero;

  Duration get position => _loaded ? _engine!.position : _pendingPosition;
  Duration? get duration => _loaded ? _engine?.duration : null;
  bool get playing => _loaded && (_engine?.playing ?? false);
  bool get buffering => busy || (_loaded && (_engine?.buffering ?? false));
  String? get error => _error ?? (_loaded ? _engine?.error : null);

  /// Preview an episode without loading audio or disturbing an active session.
  void selectEpisode(Episode selected) {
    if (_disposed ||
        !preferencesReady ||
        output != PlaybackOutput.audioPlayer ||
        busy ||
        _loaded ||
        (episode?.guid == selected.guid &&
            episode?.audioUri == selected.audioUri)) {
      return;
    }
    _episode = selected;
    _pendingPosition = Duration.zero;
    _error = null;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Duration _bounded(Duration value) {
    if (value.isNegative) return Duration.zero;
    final total = duration;
    return total != null && value > total ? total : value;
  }

  Future<void> _command(Future<void> Function() action) async {
    if (busy || _disposed) return;
    _busy = true;
    final done = Completer<void>();
    _commandDone = done;
    _error = null;
    _changed();
    try {
      await action();
    } catch (_) {
      _error = 'Audio command failed. Check your connection and try again.';
    } finally {
      _busy = false;
      done.complete();
      _changed();
    }
  }

  Future<void> playEpisode(Episode selected, {Duration? from}) {
    return _command(() async {
      if (!preferencesReady || output != PlaybackOutput.audioPlayer) return;
      final uri = EpisodeAudio.sourceFor(selected);
      if (uri == null) {
        _error = 'Audio is unavailable for this episode in this catalogue.';
        return;
      }
      if (_engine == null) {
        _engine = createEngine();
        _engine!.addListener(_changed);
      }
      final engine = _engine!;
      final repositioned =
          from != null || engine.completed || episode?.guid != selected.guid;
      final reload =
          !_loaded ||
          engine.error != null ||
          episode?.guid != selected.guid ||
          _source != uri;
      final initialPosition =
          from ?? (episode?.guid == selected.guid ? position : Duration.zero);
      if (reload) {
        await engine.pause();
        if (_disposed) return;
        _episode = selected;
        _loaded = false;
        _source = null;
        _pendingPosition = initialPosition.isNegative
            ? Duration.zero
            : initialPosition;
        await engine.load(uri, _pendingPosition);
        if (_disposed) return;
        _source = uri;
        _loaded = true;
      } else {
        if (from != null || engine.completed) {
          await engine.seek(_bounded(from ?? Duration.zero));
        }
        _episode = selected;
      }
      if (!_disposed) {
        if (repositioned) _seekRevision++;
        engine.play();
      }
    });
  }

  Future<void> toggle() {
    final selected = episode;
    if (selected == null) return Future.value();
    if (!playing) return playEpisode(selected);
    return _command(() async => _engine?.pause());
  }

  /// Capture before pausing, so replay inside the editor cannot move the bookmark.
  Future<PlaybackBookmark?> pauseForEditing() async {
    final selected = episode;
    if (_disposed || busy || output != PlaybackOutput.audioPlayer) {
      return null;
    }
    final bookmark = PlaybackBookmark._(
      selected,
      position,
      playing,
      _loaded,
      _source ?? (selected == null ? null : EpisodeAudio.sourceFor(selected)),
    );
    await _command(() async => _engine?.pause());
    return error == null ? bookmark : null;
  }

  Future<void> restoreAfterEditing(PlaybackBookmark bookmark) async {
    // A dialog can close while its Replay command is still loading audio.
    if (busy) await _commandDone?.future;
    if (_disposed || output != PlaybackOutput.audioPlayer) {
      return;
    }
    await _command(() async {
      final engine = _engine;
      await engine?.pause();
      _episode = bookmark.episode;
      _source = null;
      _loaded = false;
      _pendingPosition = bookmark.position;
      final selected = bookmark.episode;
      if (engine == null || selected == null || !bookmark.wasLoaded) return;
      final uri = EpisodeAudio.sourceFor(selected);
      if (uri == null) return;
      if (bookmark.audioUri != uri) {
        _pendingPosition = Duration.zero;
        _transcripts.remove(selected.guid);
        _seekRevision++;
        return;
      }
      await engine.load(uri, _pendingPosition);
      if (_disposed) return;
      _source = uri;
      _loaded = true;
      if (bookmark.wasPlaying) engine.play();
    });
  }

  Future<void> seek(Duration target) => _command(() async {
    if (_loaded) {
      await _engine?.seek(_bounded(target));
    } else if (episode != null) {
      _pendingPosition = target.isNegative ? Duration.zero : target;
    } else {
      return;
    }
    _seekRevision++;
  });

  Future<void> skip(Duration delta) => seek(position + delta);

  /// Stop an old edition before the new audio/text pair becomes the next play.
  Future<void> refreshPreparedEdition() async {
    if (_busy) await _commandDone?.future;
    if (_disposed) return;
    await _command(() async {
      final selected = episode;
      if (selected == null || _source == EpisodeAudio.sourceFor(selected)) {
        return;
      }
      await _engine?.stop();
      _transcripts.remove(selected.guid);
      _source = null;
      _loaded = false;
      _pendingPosition = Duration.zero;
      _seekRevision++;
    });
  }

  Future<void> close() => _command(() async {
    await _engine?.stop();
    _episode = null;
    _source = null;
    _loaded = false;
    _pendingPosition = Duration.zero;
  });

  @override
  void dispose() {
    _disposed = true;
    _transcriptEditActions.clear();
    _transcripts.clear();
    _engine?.removeListener(_changed);
    _engine?.dispose();
    super.dispose();
  }
}
