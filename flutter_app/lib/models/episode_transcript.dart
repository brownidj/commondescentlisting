import 'dart:convert';

class TranscriptCue {
  const TranscriptCue({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    required this.originalText,
    required this.reviewNotes,
  });

  final int id;
  final Duration start;
  final Duration end;
  final String text;
  final String originalText;
  final List<String> reviewNotes;

  String get timeLabel {
    String pad(int value) => value.toString().padLeft(2, '0');
    return '${pad(start.inHours)}:${pad(start.inMinutes % 60)}:'
        '${pad(start.inSeconds % 60)}';
  }
}

class EpisodeTranscript {
  const EpisodeTranscript({
    required this.episodeGuid,
    required this.label,
    required this.note,
    required this.cues,
    this.sourceDocument,
  });

  final String episodeGuid;
  final String label;
  final String note;
  final List<TranscriptCue> cues;

  /// Baseline provenance retained when exporting a locally corrected edition.
  final Map<String, dynamic>? sourceDocument;

  TranscriptCue? cueAt(Duration position) => findCueAt(cues, position);

  static TranscriptCue? findCueAt(List<TranscriptCue> cues, Duration position) {
    var low = 0;
    var high = cues.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final cue = cues[middle];
      if (position < cue.start) {
        high = middle - 1;
      } else if (position >= cue.end) {
        low = middle + 1;
      } else {
        return cue;
      }
    }
    return null;
  }

  factory EpisodeTranscript.parse(
    String source, {
    required String episodeGuid,
  }) {
    final document = jsonDecode(source);
    if (document is! Map<String, dynamic> ||
        document['schema_version'] != 1 ||
        document['episode_guid'] != episodeGuid) {
      throw const FormatException('Transcript identity or schema is invalid.');
    }
    final review = document['review'];
    final segments = document['segments'];
    final changes = document['changes'];
    final unresolved = document['unresolved'];
    if (review is! Map<String, dynamic> ||
        review['label'] is! String ||
        review['note'] is! String ||
        segments is! List ||
        segments.isEmpty ||
        changes is! List ||
        unresolved is! List) {
      throw const FormatException('Transcript content is invalid.');
    }
    final originals = <int, String>{};
    for (final change in changes) {
      if (change is! Map<String, dynamic> ||
          change['line'] is! int ||
          change['original_text'] is! String) {
        throw const FormatException('Transcript correction is invalid.');
      }
      final line = change['line'] as int;
      if (originals.containsKey(line)) {
        throw const FormatException('Transcript correction is duplicated.');
      }
      originals[line] = (change['original_text'] as String).trim();
    }
    final notes = <int, List<String>>{};
    for (final flag in unresolved) {
      if (flag is! Map<String, dynamic> ||
          flag['lines'] is! List ||
          flag['reason'] is! String) {
        throw const FormatException('Transcript review flag is invalid.');
      }
      final flagLines = <int>{};
      for (final line in flag['lines'] as List) {
        if (line is! int || !flagLines.add(line)) {
          throw const FormatException('Transcript review cue is invalid.');
        }
        notes.putIfAbsent(line, () => []).add(flag['reason'] as String);
      }
    }
    final cues = <TranscriptCue>[];
    var previousId = 0;
    var previousEnd = 0;
    for (final segment in segments) {
      if (segment is! Map<String, dynamic>) {
        throw const FormatException('Transcript cue is invalid.');
      }
      final id = segment['id'];
      final start = segment['start_ms'];
      final end = segment['end_ms'];
      final text = segment['text'];
      if (id is! int ||
          id <= previousId ||
          start is! int ||
          start < previousEnd ||
          end is! int ||
          end <= start ||
          text is! String ||
          text.trim().isEmpty) {
        throw const FormatException(
          'Transcript cue timing or text is invalid.',
        );
      }
      cues.add(
        TranscriptCue(
          id: id,
          start: Duration(milliseconds: start),
          end: Duration(milliseconds: end),
          text: text,
          originalText: originals[id] ?? text,
          reviewNotes: List.unmodifiable(notes[id] ?? <String>[]),
        ),
      );
      previousId = id;
      previousEnd = end;
    }
    final cueIds = cues.map((cue) => cue.id).toSet();
    if (originals.keys.any((id) => !cueIds.contains(id)) ||
        notes.keys.any((id) => !cueIds.contains(id))) {
      throw const FormatException('Transcript review reference is invalid.');
    }
    return EpisodeTranscript(
      episodeGuid: episodeGuid,
      label: review['label'] as String,
      note: review['note'] as String,
      cues: List.unmodifiable(cues),
      sourceDocument: document,
    );
  }
}
