import '../../models/episode_transcript.dart';

/// Literal, case-insensitive matching within each displayed transcript passage.
class TranscriptSearch {
  factory TranscriptSearch(String input) {
    final query = input.trim();
    return TranscriptSearch._(
      query,
      query.isEmpty
          ? null
          : RegExp(RegExp.escape(query), caseSensitive: false, unicode: true),
    );
  }

  const TranscriptSearch._(this.query, this._pattern);

  final String query;
  final RegExp? _pattern;
  bool get isActive => _pattern != null;

  Iterable<RegExpMatch> matches(String text) =>
      _pattern?.allMatches(text) ?? const <RegExpMatch>[];

  List<TranscriptCue> filter(
    Iterable<TranscriptCue> cues, {
    required bool original,
  }) => cues
      .where(
        (cue) =>
            !isActive ||
            _pattern!.hasMatch(original ? cue.originalText : cue.text),
      )
      .toList(growable: false);
}
