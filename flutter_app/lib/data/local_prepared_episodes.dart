import 'package:flutter/foundation.dart';

import '../models/episode_transcript.dart';
import '../models/transcript_alignment.dart';

/// Completed local editions override a bundle only as a validated audio/text pair.
class LocalPreparedEdition {
  const LocalPreparedEdition({
    required this.guid,
    required this.edition,
    required this.audioUri,
    required this.audioIdentity,
    required this.duration,
    required this.passageCount,
    required this.loadText,
    this.hasIndex = false,
    this.readOnly = false,
  });
  final bool hasIndex;
  final bool readOnly;
  final String guid;
  final String edition;
  final Uri audioUri;
  final String audioIdentity;
  final Duration duration;
  final int passageCount;
  final Future<String> Function(String file) loadText;

  Future<EpisodeTranscript> loadTranscript() async {
    final baseline = EpisodeTranscript.parse(
      await loadText('transcript/baseline.json'),
      episodeGuid: guid,
    );
    final result = applyTranscriptAlignment(
      baseline,
      await loadText('transcript/alignment.json'),
      audioIdentity: audioIdentity,
      audioDuration: duration,
    );
    if (result.cues.length != passageCount) {
      throw const FormatException('Local transcript coverage is invalid.');
    }
    return result;
  }
}

class LocalPreparedEpisodes {
  static Map<String, LocalPreparedEdition> _editions = {};
  static Map<String, LocalPreparedEdition> _remote = {};
  static void replaceRemote(Iterable<LocalPreparedEdition> editions) {
    _remote = {for (final edition in editions) edition.guid: edition};
    changes.value++;
  }

  static final changes = ValueNotifier<int>(0);
  static Iterable<LocalPreparedEdition> get editions =>
      {..._remote, ..._editions}.values;
  static LocalPreparedEdition? forGuid(String guid) =>
      _editions[guid] ?? _remote[guid];
  static void replace(Iterable<LocalPreparedEdition> editions) {
    final next = {for (final edition in editions) edition.guid: edition};
    final changed =
        next.length != _editions.length ||
        next.entries.any(
          (entry) =>
              _editions[entry.key]?.edition != entry.value.edition ||
              _editions[entry.key]?.audioUri != entry.value.audioUri ||
              _editions[entry.key]?.hasIndex != entry.value.hasIndex,
        );
    _editions = next;
    if (changed) changes.value++;
  }
}
