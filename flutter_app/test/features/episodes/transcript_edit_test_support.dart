import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';

class MemoryTranscriptEditStore implements TranscriptEditStore {
  final documents = <String, String>{};
  bool failSave = false;
  bool failRead = false;

  @override
  Future<String?> read(String guid) async {
    if (failRead) throw StateError('Read failure');
    return documents[guid];
  }

  @override
  Future<bool> writeIfUnchanged(
    String guid, {
    required String? expectedDocument,
    required String document,
  }) async {
    if (failSave) throw StateError('Write failure');
    if (documents[guid] != expectedDocument) return false;
    documents[guid] = document;
    return true;
  }
}

const editableTranscript = EpisodeTranscript(
  episodeGuid: 'test-transcript',
  label: 'Reviewed transcript',
  note: 'Context review only.',
  cues: [
    TranscriptCue(
      id: 1,
      start: Duration.zero,
      end: Duration(seconds: 10),
      text: 'Karoo rocks.',
      originalText: 'Karu rocks.',
      reviewNotes: [],
    ),
    TranscriptCue(
      id: 2,
      start: Duration(seconds: 10),
      end: Duration(seconds: 20),
      text: 'Some fossils.',
      originalText: 'Some fossils.',
      reviewNotes: ['Check this.'],
    ),
  ],
);
