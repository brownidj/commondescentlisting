import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/episode_transcript.dart';

abstract interface class TranscriptEditStore {
  Future<String?> read(String guid);
  Future<bool> writeIfUnchanged(
    String guid, {
    required String? expectedDocument,
    required String document,
  });
}

class ReadOnlyTranscriptEditStore implements TranscriptEditStore {
  @override
  Future<String?> read(String guid) async => null;
  @override
  Future<bool> writeIfUnchanged(
    String guid, {
    required String? expectedDocument,
    required String document,
  }) async => false;
}

class TranscriptEditConflict implements Exception {
  const TranscriptEditConflict();
}

class TranscriptRevision {
  const TranscriptRevision({
    required this.cueId,
    required this.startMs,
    required this.endMs,
    required this.baselineText,
    required this.before,
    required this.after,
    required this.date,
  });

  final int cueId;
  final int startMs;
  final int endMs;
  final String baselineText;
  final String before;
  final String after;
  final DateTime date;

  Map<String, dynamic> toJson() => {
    'cue_id': cueId,
    'start_ms': startMs,
    'end_ms': endMs,
    'baseline_text': baselineText,
    'before': before,
    'after': after,
    'date': date.toUtc().toIso8601String(),
  };

  factory TranscriptRevision.parse(dynamic value) {
    if (value is! Map<String, dynamic> ||
        value['cue_id'] is! int ||
        value['start_ms'] is! int ||
        value['end_ms'] is! int ||
        value['baseline_text'] is! String ||
        value['before'] is! String ||
        value['after'] is! String ||
        value['date'] is! String) {
      throw const FormatException('Invalid transcript revision.');
    }
    final after = value['after'] as String;
    if (after.trim().isEmpty || after.length > 20000) {
      throw const FormatException('Invalid passage text.');
    }
    return TranscriptRevision(
      cueId: value['cue_id'] as int,
      startMs: value['start_ms'] as int,
      endMs: value['end_ms'] as int,
      baselineText: value['baseline_text'] as String,
      before: value['before'] as String,
      after: after,
      date: DateTime.parse(value['date'] as String),
    );
  }
}

class TranscriptEdits extends ChangeNotifier {
  TranscriptEdits({required this.baseline, required this.store});
  // Opening adverts can exceed 30 seconds. Share one bound for reads and writes.
  static const maxSyncOffset = Duration(minutes: 10);
  final EpisodeTranscript baseline;
  final TranscriptEditStore store;
  List<TranscriptRevision> _history = [];
  Map<int, String> _text = {};
  Duration _syncOffset = Duration.zero;
  EpisodeTranscript? _currentCache;
  String? _savedDocument;
  bool conflict = false;
  Duration get syncOffset => _syncOffset;

  /// Positive offsets show a passage earlier; seek to its earlier audio time.
  Duration audioStart(TranscriptCue cue) {
    final target = cue.start - _syncOffset;
    return target.isNegative ? Duration.zero : target;
  }

  bool ready = false;
  bool busy = false;
  String? loadError;
  bool _disposed = false;

  List<TranscriptRevision> get history => List.unmodifiable(_history);
  String textFor(TranscriptCue cue) => _text[cue.id] ?? cue.text;
  bool edited(TranscriptCue cue) =>
      textFor(cue) !=
      baseline.cues.firstWhere((baselineCue) => baselineCue.id == cue.id).text;

  EpisodeTranscript get current => _currentCache ??= EpisodeTranscript(
    episodeGuid: baseline.episodeGuid,
    label: baseline.label,
    note: baseline.note,
    sourceDocument: baseline.sourceDocument,
    audioIdentity: baseline.audioIdentity,
    cues: List.unmodifiable(
      baseline.cues.map(
        (cue) => TranscriptCue(
          id: cue.id,
          start: cue.start,
          end: cue.end,
          text: textFor(cue),
          originalText: cue.originalText,
          reviewNotes: cue.reviewNotes,
          sourceStart: cue.sourceStart,
          sourceEnd: cue.sourceEnd,
        ),
      ),
    ),
  );

  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (busy) {
      return;
    }
    busy = true;
    ready = false;
    loadError = null;
    _changed();
    try {
      final saved = await store.read(baseline.episodeGuid);
      final history = <TranscriptRevision>[];
      final text = <int, String>{};
      var offset = Duration.zero;
      if (saved != null) {
        final document = jsonDecode(saved);
        if (document is! Map<String, dynamic> ||
            document['schema_version'] != 1 ||
            document['episode_guid'] != baseline.episodeGuid ||
            document['revisions'] is! List) {
          throw const FormatException('Invalid transcript journal.');
        }
        final offsetMs = document['sync_offset_ms'] ?? 0;
        if (offsetMs is! int || offsetMs.abs() > maxSyncOffset.inMilliseconds) {
          throw const FormatException('Invalid transcript timing adjustment.');
        }
        offset = Duration(milliseconds: offsetMs);
        final savedIdentity =
            document['sync_offset_audio_identity'] ?? 'legacy-stream';
        final offsets = document['sync_offsets_ms'] ?? <String, dynamic>{};
        if (savedIdentity is! String ||
            offsets is! Map<String, dynamic> ||
            offsets.values.any(
              (value) =>
                  value is! int || value.abs() > maxSyncOffset.inMilliseconds,
            )) {
          throw const FormatException(
            'Audio calibration identities are invalid.',
          );
        }
        final currentIdentity = baseline.audioIdentity ?? 'legacy-stream';
        if (savedIdentity != currentIdentity) {
          offset = Duration(
            milliseconds: (offsets[currentIdentity] as int?) ?? 0,
          );
        }
        final cues = {for (final cue in baseline.cues) cue.id: cue};
        for (final value in document['revisions'] as List) {
          final revision = TranscriptRevision.parse(value);
          final cue = cues[revision.cueId];
          if (cue == null ||
              cue.revisionStart.inMilliseconds != revision.startMs ||
              cue.revisionEnd.inMilliseconds != revision.endMs ||
              cue.text != revision.baselineText ||
              (text[cue.id] ?? cue.text) != revision.before) {
            throw const FormatException('Transcript baseline has changed.');
          }
          history.add(revision);
          text[cue.id] = revision.after;
        }
      }
      _history = history;
      _text = text;
      _currentCache = null;
      _syncOffset = offset;
      _savedDocument = saved;
      conflict = false;
      ready = true;
    } catch (_) {
      _history = [];
      _text = {};
      _currentCache = null;
      _syncOffset = Duration.zero;
      loadError =
          'Saved corrections could not be loaded or no longer match this '
          'transcript. They have been kept. Editing and export are disabled; '
          'the bundled transcript is shown.';
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> save(int cueId, String input) async {
    if (conflict) throw const TranscriptEditConflict();
    if (!ready || busy) {
      throw StateError('Corrections are not ready.');
    }
    final text = input.trim();
    if (text.isEmpty || text.length > 20000) {
      throw const FormatException('Enter between 1 and 20,000 characters.');
    }
    final cue = baseline.cues.firstWhere((cue) => cue.id == cueId);
    if (textFor(cue) == text) return;
    final next = [
      ..._history,
      TranscriptRevision(
        cueId: cue.id,
        startMs: cue.revisionStart.inMilliseconds,
        endMs: cue.revisionEnd.inMilliseconds,
        baselineText: cue.text,
        before: textFor(cue),
        after: text,
        date: DateTime.now().toUtc(),
      ),
    ];
    busy = true;
    _changed();
    try {
      await _write(next, _syncOffset);
      _history = next;
      _text = {..._text, cueId: text};
      _currentCache = null;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _write(List<TranscriptRevision> history, Duration offset) async {
    final previous = _savedDocument == null
        ? <String, dynamic>{}
        : jsonDecode(_savedDocument!) as Map<String, dynamic>;
    final identity = baseline.audioIdentity ?? 'legacy-stream';
    final offsets = <String, dynamic>{
      ...?previous['sync_offsets_ms'] as Map<String, dynamic>?,
      if (previous.containsKey('sync_offset_ms'))
        (previous['sync_offset_audio_identity'] as String? ?? 'legacy-stream'):
            previous['sync_offset_ms'],
      identity: offset.inMilliseconds,
    };
    final document = jsonEncode({
      ...previous,
      'schema_version': 1,
      'episode_guid': baseline.episodeGuid,
      'sync_offset_ms': offset.inMilliseconds,
      'sync_offset_audio_identity': identity,
      'sync_offsets_ms': offsets,
      'revisions': history.map((revision) => revision.toJson()).toList(),
    });
    final written = await store.writeIfUnchanged(
      baseline.episodeGuid,
      expectedDocument: _savedDocument,
      document: document,
    );
    if (!written) {
      conflict = true;
      ready = false;
      throw const TranscriptEditConflict();
    }
    _savedDocument = document;
  }

  Future<void> setSyncOffset(Duration offset) async {
    if (conflict) throw const TranscriptEditConflict();
    if (!ready || busy) {
      throw StateError('Corrections are not ready.');
    }
    if (offset.inMicroseconds.abs() > maxSyncOffset.inMicroseconds ||
        offset.inMicroseconds % 1000 != 0) {
      throw const FormatException(
        'Timing adjustment must be within 10 minutes.',
      );
    }
    if (offset == _syncOffset) return;
    busy = true;
    _changed();
    try {
      await _write(_history, offset);
      _syncOffset = offset;
    } finally {
      busy = false;
      _changed();
    }
  }

  /// Anchor the selected passage to a measured audio time, without seeking.
  Future<void> alignCueToAudio(int cueId, Duration audioPosition) async {
    if (audioPosition.isNegative) {
      throw const FormatException('Audio position cannot be negative.');
    }
    final cue = baseline.cues.firstWhere((cue) => cue.id == cueId);
    final offset = Duration(
      milliseconds: (cue.start - audioPosition).inMilliseconds,
    );
    if (offset.inMilliseconds.abs() > maxSyncOffset.inMilliseconds) {
      throw const FormatException(
        'This passage is more than 10 minutes from the audio clock. '
        'Choose the passage you are hearing.',
      );
    }
    await setSyncOffset(offset);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
