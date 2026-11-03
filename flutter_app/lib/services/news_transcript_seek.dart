import '../models/catalogue.dart';
import '../models/episode_transcript.dart';
import 'current_transcript.dart';

class NewsSeekTarget {
  const NewsSeekTarget({required this.time, required this.message, this.cue});
  final Duration? time;
  final String message;
  final TranscriptCue? cue;
}

Duration? newsSectionStart(Episode episode) => episode.segments
    .where((s) => s.isNews)
    .map(
      (s) =>
          s.newsStartTime ??
          ((s.title?.trim().isEmpty ?? true) ? s.startTime : null),
    )
    .whereType<Duration>()
    .firstOrNull;

Set<String> _keywords(String text) {
  const stop = {
    'a',
    'an',
    'the',
    'and',
    'or',
    'of',
    'to',
    'in',
    'on',
    'for',
    'from',
    'with',
    'about',
    'is',
    'are',
    'was',
    'were',
    'this',
    'that',
    'some',
    'more',
    'new',
    'old',
    'big',
    'small',
    'great',
    'very',
    'ancient',
    'early',
    'study',
    'research',
    'news',
    'paper',
    'article',
  };
  return RegExp(r'[a-z]+')
      .allMatches(text.toLowerCase())
      .map((m) => m.group(0)!)
      .where((word) => word.length > 2 && !stop.contains(word))
      .map(
        (word) => word.endsWith('ies') && word.length > 5
            ? '${word.substring(0, word.length - 3)}y'
            : word.endsWith('s') &&
                  !word.endsWith('ss') &&
                  !word.endsWith('us') &&
                  word.length > 4
            ? word.substring(0, word.length - 1)
            : word,
      )
      .toSet();
}

/// Estimates a passage match, not an acoustically verified item boundary.
NewsSeekTarget matchNewsPassage(
  Episode episode,
  Segment selected,
  CurrentTranscript document,
) {
  final fallback = newsSectionStart(episode);
  NewsSeekTarget fail(String reason) => NewsSeekTarget(
    time: selected.startTime ?? fallback,
    message:
        '$reason ${selected.startTime != null
            ? "Using the published item time."
            : fallback == null
            ? "No section start time is available."
            : "Play starts the whole news section, not the selected item."}',
  );
  final wanted = _keywords(selected.title ?? '');
  if (wanted.isEmpty) {
    return fail('No distinctive headline words to match.');
  }
  final peers = episode.segments.where(
    (s) => s.isNews && s.sessionId != selected.sessionId,
  );
  if (peers.any((s) {
    final words = _keywords(s.title ?? '');
    return words.length == wanted.length && words.containsAll(wanted);
  })) {
    return fail('Similar headlines cannot be distinguished reliably.');
  }
  final discussionTimes =
      episode.segments
          .where((s) => s.type == 'Main Discussion')
          .map((s) => s.startTime)
          .whereType<Duration>()
          .toList()
        ..sort();
  // Without a bounded News window, discussion mentions could be false matches.
  if (fallback == null ||
      discussionTimes.isEmpty ||
      discussionTimes.first <= fallback) {
    return fail('The news portion cannot be bounded reliably.');
  }
  final candidates = <({TranscriptCue cue, double score})>[];
  for (final cue in document.transcript.cues) {
    final audioTime = document.audioStart(cue);
    if (audioTime < fallback || audioTime >= discussionTimes.first) {
      continue;
    }
    final words = _keywords(cue.text);
    final coverage = wanted.intersection(words).length / wanted.length;
    if (coverage < .7) {
      continue;
    }
    // Skip an introductory list mentioning several indexed news stories.
    if (peers.any((s) {
      final other = _keywords(s.title ?? '');
      return other.isNotEmpty &&
          other.intersection(words).length / other.length >= .7;
    })) {
      continue;
    }
    if (wanted.length == 1 && wanted.single.length < 7) {
      continue;
    }
    candidates.add((cue: cue, score: coverage));
  }
  if (candidates.isEmpty) {
    return fail('No confident transcript match for this headline.');
  }
  final groups = <List<({TranscriptCue cue, double score})>>[];
  for (final hit in candidates) {
    if (groups.isEmpty ||
        hit.cue.start - groups.last.last.cue.end >
            const Duration(seconds: 90)) {
      groups.add([]);
    }
    groups.last.add(hit);
  }
  // Repeated, separated topic mentions could belong to different stories.
  if (groups.length != 1) {
    return fail('Several separated transcript matches need review.');
  }
  if (wanted.length == 1 && candidates.length < 2) {
    return fail('Only one weak topic mention was found.');
  }
  final cue = groups.single.first.cue;
  return NewsSeekTarget(
    time: document.audioStart(cue),
    cue: cue,
    message:
        'Transcript match: passage ${cue.id}. This is a text match, not a verified story boundary.',
  );
}
