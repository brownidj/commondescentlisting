import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:common_descent_listing/features/indexes/index_store.dart';
import 'package:common_descent_listing/models/catalogue.dart';
import 'package:common_descent_listing/models/episode_transcript.dart';

class MemoryIndexStore implements IndexRegistryStore {
  String? document;
  bool refuse = false;
  @override
  Future<String?> read() async => document;
  @override
  Future<bool> save(String next, {required String? expected}) async {
    if (refuse || document != expected) {
      return false;
    }
    document = next;
    return true;
  }
}

CurrentTranscript indexDocument(
  List<String> texts, {
  String edition = 'one',
  Duration offset = Duration.zero,
}) => CurrentTranscript(
  episode: Episode(
    guid: 'episode',
    title: 'Sample episode',
    number: '208',
    segments: const [],
  ),
  edition: edition,
  syncOffset: offset,
  transcript: EpisodeTranscript(
    episodeGuid: 'episode',
    label: 'Machine transcribed',
    note: 'Not reviewed',
    audioIdentity: 'sha256:$edition',
    cues: [
      for (var i = 0; i < texts.length; i++)
        TranscriptCue(
          id: i + 1,
          start: Duration(seconds: i * 5),
          end: Duration(seconds: i * 5 + 5),
          text: texts[i],
          originalText: texts[i],
          reviewNotes: const [],
        ),
    ],
  ),
);
Catalogue indexCatalogue(CurrentTranscript d) => Catalogue(
  podcast: const Podcast(title: 'Podcast'),
  episodes: [d.episode],
  segments: const [],
  sourceName: 'fixture',
);
