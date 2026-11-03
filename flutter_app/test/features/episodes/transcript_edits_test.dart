import 'dart:convert';
import 'dart:io';

import 'package:common_descent_listing/models/episode_transcript.dart';
import 'package:common_descent_listing/services/file_transcript_edits.dart';
import 'package:common_descent_listing/services/transcript_edits.dart';
import 'package:common_descent_listing/services/transcript_export.dart';
import 'package:flutter_test/flutter_test.dart';

import 'transcript_edit_test_support.dart';

void main() {
  test(
    'advert-length calibration reloads, preserves edits and seeks correctly',
    () async {
      final store = MemoryTranscriptEditStore();
      final edits = TranscriptEdits(baseline: editableTranscript, store: store);
      addTearDown(edits.dispose);
      await edits.load();
      await edits.save(2, 'Corrected fossils.');
      await edits.alignCueToAudio(2, const Duration(milliseconds: 41001));
      expect(edits.syncOffset, const Duration(milliseconds: -31001));
      expect(
        edits.audioStart(editableTranscript.cues[1]),
        const Duration(milliseconds: 41001),
      );
      expect(
        edits.current
            .cueAt(const Duration(milliseconds: 41001) + edits.syncOffset)
            ?.id,
        2,
      );
      final reopened = TranscriptEdits(
        baseline: editableTranscript,
        store: store,
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.ready, isTrue);
      expect(reopened.syncOffset, const Duration(milliseconds: -31001));
      expect(reopened.history, hasLength(1));
      expect(reopened.current.cues[1].text, 'Corrected fossils.');
      expect(reopened.current.cues[1].start, const Duration(seconds: 10));
      for (final sign in [-1, 1]) {
        await reopened.setSyncOffset(Duration(minutes: sign * 10));
        await reopened.load();
        expect(reopened.ready, isTrue);
        expect(reopened.syncOffset, Duration(minutes: sign * 10));
        final document = store.documents[editableTranscript.episodeGuid];
        await expectLater(
          reopened.setSyncOffset(Duration(milliseconds: sign * 600001)),
          throwsFormatException,
        );
        expect(store.documents[editableTranscript.episodeGuid], document);
        final invalid = jsonDecode(document!) as Map<String, dynamic>;
        invalid['sync_offset_ms'] = sign * 600001;
        store.documents[editableTranscript.episodeGuid] = jsonEncode(invalid);
        await reopened.load();
        expect(reopened.ready, isFalse);
        store.documents[editableTranscript.episodeGuid] = document;
        await reopened.load();
      }
    },
  );

  test(
    'measured passage sync has the correct sign and does not accumulate',
    () async {
      final store = MemoryTranscriptEditStore();
      final edits = TranscriptEdits(baseline: editableTranscript, store: store);
      addTearDown(edits.dispose);
      await edits.load();
      final snapshot = edits.current;
      await edits.alignCueToAudio(2, const Duration(seconds: 4));
      expect(edits.syncOffset, const Duration(seconds: 6));
      expect(
        edits.audioStart(editableTranscript.cues[1]),
        const Duration(seconds: 4),
      );
      await edits.alignCueToAudio(2, const Duration(seconds: 4));
      expect(edits.syncOffset, const Duration(seconds: 6));
      expect(identical(snapshot, edits.current), isTrue);
      expect(edits.history, isEmpty);
      await edits.alignCueToAudio(2, const Duration(seconds: 16));
      expect(edits.syncOffset, const Duration(seconds: -6));
      expect(
        edits.audioStart(editableTranscript.cues[1]),
        const Duration(seconds: 16),
      );
      await expectLater(
        edits.alignCueToAudio(2, const Duration(minutes: 11)),
        throwsFormatException,
      );
      expect(edits.syncOffset, const Duration(seconds: -6));
      store.failSave = true;
      await expectLater(
        edits.alignCueToAudio(2, const Duration(seconds: 4)),
        throwsStateError,
      );
      expect(edits.syncOffset, const Duration(seconds: -6));
      store.failSave = false;
      await edits.save(2, 'Newly corrected words.');
      expect(identical(snapshot, edits.current), isFalse);
      expect(edits.current.cues[1].text, 'Newly corrected words.');
    },
  );

  test('legacy journals use zero offset and invalid calibration is retained safely', () async {
    final store = MemoryTranscriptEditStore();
    final journal = <String, dynamic>{
      'schema_version': 1,
      'episode_guid': editableTranscript.episodeGuid,
      'revisions': [],
    };
    store.documents[editableTranscript.episodeGuid] = jsonEncode(journal);
    final edits = TranscriptEdits(baseline: editableTranscript, store: store);
    addTearDown(edits.dispose);
    await edits.load();
    expect(edits.ready, isTrue);
    expect(edits.syncOffset, Duration.zero);
    journal['sync_offset_ms'] = 'bad';
    final invalid = jsonEncode(journal);
    store.documents[editableTranscript.episodeGuid] = invalid;
    await edits.load();
    expect(edits.ready, isFalse);
    expect(store.documents[editableTranscript.episodeGuid], invalid);
  });

  test(
    'timing adjustment persists without changing text, history or timestamps',
    () async {
      final store = MemoryTranscriptEditStore();
      final edits = TranscriptEdits(baseline: editableTranscript, store: store);
      addTearDown(edits.dispose);
      await edits.load();
      await edits.save(2, 'Corrected fossils.');
      await edits.setSyncOffset(const Duration(seconds: 6));
      expect(
        edits.audioStart(editableTranscript.cues[1]),
        const Duration(seconds: 4),
      );
      expect(edits.audioStart(editableTranscript.cues[0]), Duration.zero);
      final reopened = TranscriptEdits(
        baseline: editableTranscript,
        store: store,
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.syncOffset, const Duration(seconds: 6));
      expect(reopened.history, hasLength(1));
      expect(reopened.current.cues[1].text, 'Corrected fossils.');
      expect(reopened.current.cues[1].start, const Duration(seconds: 10));
      final exported = jsonDecode(
        transcriptExportFiles(reopened, 'test')['test.json']!,
      );
      expect(exported['playback_sync_offset_ms'], 6000);
      expect(exported['segments'][1]['start_ms'], 10000);
      store.failSave = true;
      await expectLater(
        reopened.setSyncOffset(Duration.zero),
        throwsStateError,
      );
      expect(reopened.syncOffset, const Duration(seconds: 6));
      store.failSave = false;
      await reopened.setSyncOffset(const Duration(seconds: -2));
      expect(
        reopened.audioStart(editableTranscript.cues[1]),
        const Duration(seconds: 12),
      );
      await reopened.setSyncOffset(Duration.zero);
      expect(reopened.syncOffset, Duration.zero);
      await expectLater(
        reopened.setSyncOffset(const Duration(minutes: 11)),
        throwsFormatException,
      );
    },
  );

  test(
    'edits and restores survive reload with history and protected times',
    () async {
      final store = MemoryTranscriptEditStore();
      final edits = TranscriptEdits(baseline: editableTranscript, store: store);
      addTearDown(edits.dispose);
      await edits.load();
      await edits.save(1, 'Karoo basin rocks.');
      await edits.save(1, editableTranscript.cues.first.originalText);
      final restored = TranscriptEdits(
        baseline: editableTranscript,
        store: store,
      );
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.ready, isTrue);
      expect(restored.current.cues.first.text, 'Karu rocks.');
      expect(restored.current.cues.first.originalText, 'Karu rocks.');
      expect(restored.history, hasLength(2));
      expect(restored.history.last.before, 'Karoo basin rocks.');
      expect(restored.current.cues.first.start, Duration.zero);
      expect(restored.current.cues.first.end, const Duration(seconds: 10));
    },
  );

  test('failed saves and empty text preserve saved text/history', () async {
    final store = MemoryTranscriptEditStore();
    final edits = TranscriptEdits(baseline: editableTranscript, store: store);
    addTearDown(edits.dispose);
    await edits.load();
    await edits.save(2, 'Revised fossils.');
    final saved = store.documents[editableTranscript.episodeGuid];
    store.failSave = true;
    await expectLater(edits.save(2, 'Unsaved fossils.'), throwsStateError);
    await expectLater(edits.save(2, '  '), throwsFormatException);
    expect(edits.current.cues[1].text, 'Revised fossils.');
    expect(edits.history, hasLength(1));
    expect(store.documents[editableTranscript.episodeGuid], saved);
    expect(edits.busy, isFalse);
  });

  test('stale editor reloads the latest snapshot before saving', () async {
    final store = MemoryTranscriptEditStore();
    final first = TranscriptEdits(baseline: editableTranscript, store: store);
    final second = TranscriptEdits(baseline: editableTranscript, store: store);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait([first.load(), second.load()]);

    await first.save(1, 'First editor correction.');
    await expectLater(
      second.save(2, 'Second editor correction.'),
      throwsA(isA<TranscriptEditConflict>()),
    );
    expect(second.conflict, isTrue);
    expect(second.ready, isFalse);
    expect(first.current.cues.first.text, 'First editor correction.');
    expect(store.documents[editableTranscript.episodeGuid], isNotNull);

    await second.load();
    expect(second.conflict, isFalse);
    await second.save(2, 'Second editor correction.');
    final reopened = TranscriptEdits(
      baseline: editableTranscript,
      store: store,
    );
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.current.cues[0].text, 'First editor correction.');
    expect(reopened.current.cues[1].text, 'Second editor correction.');
    expect(reopened.history, hasLength(2));
  });

  test('stale sync offsets cannot overwrite a newer snapshot', () async {
    final store = MemoryTranscriptEditStore();
    final first = TranscriptEdits(baseline: editableTranscript, store: store);
    final second = TranscriptEdits(baseline: editableTranscript, store: store);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await Future.wait([first.load(), second.load()]);

    await first.setSyncOffset(const Duration(seconds: 6));
    await expectLater(
      second.setSyncOffset(const Duration(seconds: -6)),
      throwsA(isA<TranscriptEditConflict>()),
    );
    expect(second.syncOffset, Duration.zero);
    expect(second.conflict, isTrue);
    expect(second.ready, isFalse);

    await second.load();
    expect(second.syncOffset, const Duration(seconds: 6));
    await second.setSyncOffset(const Duration(seconds: -6));
    final reopened = TranscriptEdits(
      baseline: editableTranscript,
      store: store,
    );
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.syncOffset, const Duration(seconds: -6));
  });

  test(
    'malformed or stale journal is retained and disables saving/export',
    () async {
      final store = MemoryTranscriptEditStore();
      store.documents[editableTranscript.episodeGuid] = '{damaged';
      final edits = TranscriptEdits(baseline: editableTranscript, store: store);
      addTearDown(edits.dispose);
      await edits.load();
      expect(edits.ready, isFalse);
      expect(edits.loadError, isNotNull);
      expect(store.documents[editableTranscript.episodeGuid], '{damaged');
      expect(() => transcriptExportFiles(edits, 'test'), throwsStateError);
      store.documents.clear();
      await edits.load();
      await edits.save(1, 'New wording.');
      final journal =
          jsonDecode(store.documents[editableTranscript.episodeGuid]!) as Map;
      (journal['revisions'] as List).first['start_ms'] = 1;
      final stale = jsonEncode(journal);
      store.documents[editableTranscript.episodeGuid] = stale;
      final reopened = TranscriptEdits(
        baseline: editableTranscript,
        store: store,
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.ready, isFalse);
      expect(store.documents[editableTranscript.episodeGuid], stale);
      expect(reopened.current.cues.first.text, 'Karoo rocks.');
    },
  );

  test(
    'all exports share saved text, original identity and cue timings',
    () async {
      final edits = TranscriptEdits(
        baseline: editableTranscript,
        store: MemoryTranscriptEditStore(),
      );
      addTearDown(edits.dispose);
      await edits.load();
      await edits.save(2, 'Corrected fossils & <names>.');
      final files = transcriptExportFiles(edits, 'reviewed');
      expect(
        files.keys,
        containsAll([
          'reviewed.json',
          'reviewed.txt',
          'reviewed.vtt',
          'reviewed.srt',
        ]),
      );
      final reparsed = EpisodeTranscript.parse(
        files['reviewed.json']!,
        episodeGuid: editableTranscript.episodeGuid,
      );
      expect(reparsed.cues[1].text, 'Corrected fossils & <names>.');
      expect(reparsed.cues[1].originalText, 'Some fossils.');
      expect(reparsed.cues[1].start, const Duration(seconds: 10));
      expect(reparsed.cues[1].reviewNotes, ['Check this.']);
      expect(files['reviewed.txt'], contains(reparsed.cues[1].text));
      expect(files['reviewed.vtt'], contains('00:00:10.000 --> 00:00:20.000'));
      expect(
        files['reviewed.vtt'],
        contains('Corrected fossils &amp; &lt;names&gt;.'),
      );
      expect(
        files['reviewed.srt'],
        contains('2\n00:00:10,000 --> 00:00:20,000'),
      );
      expect(
        jsonDecode(files['reviewed.json']!)['local_revision_history'],
        hasLength(1),
      );
    },
  );

  test(
    'file journal round trip and interrupted staging file is ignored',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'transcript-edit-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileTranscriptEditStore(directory: () async => directory);
      final edits = TranscriptEdits(baseline: editableTranscript, store: store);
      addTearDown(edits.dispose);
      await edits.load();
      await edits.save(2, 'Saved on disk.');
      await edits.setSyncOffset(const Duration(milliseconds: -31001));
      await edits.setSyncOffset(
        edits.syncOffset + const Duration(milliseconds: 500),
      );
      final file =
          (await Directory('${directory.path}/transcript-edits')
                  .list()
                  .where((entity) => entity.path.endsWith('.json'))
                  .single)
              as File;
      await File('${file.path}.pending').writeAsString('incomplete');
      expect(jsonDecode(await file.readAsString())['sync_offset_ms'], -30501);
      final reopened = TranscriptEdits(
        baseline: editableTranscript,
        store: FileTranscriptEditStore(directory: () async => directory),
      );
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.current.cues[1].text, 'Saved on disk.');
      expect(reopened.syncOffset, const Duration(milliseconds: -30501));
      expect(reopened.history, hasLength(1));
      await reopened.setSyncOffset(
        reopened.syncOffset - const Duration(milliseconds: 500),
      );
      await edits.load();
      expect(edits.syncOffset, const Duration(milliseconds: -31001));
      await file.writeAsString('{bad');
      await reopened.load();
      expect(reopened.ready, isFalse);
      expect(await file.readAsString(), '{bad');
    },
  );

  test(
    'file-store instances serialize conditional writes to one snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'transcript-edit-concurrent-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final first = FileTranscriptEditStore(directory: () async => directory);
      final second = FileTranscriptEditStore(directory: () async => directory);
      const guid = 'concurrent-transcript';

      final results = await Future.wait([
        first.writeIfUnchanged(
          guid,
          expectedDocument: null,
          document: 'first snapshot',
        ),
        second.writeIfUnchanged(
          guid,
          expectedDocument: null,
          document: 'second snapshot',
        ),
      ]);
      expect(results.where((written) => written), hasLength(1));
      final saved = await first.read(guid);
      expect(saved, anyOf('first snapshot', 'second snapshot'));
      expect(
        await second.writeIfUnchanged(
          guid,
          expectedDocument: null,
          document: 'stale snapshot',
        ),
        isFalse,
      );
      expect(await first.read(guid), saved);
    },
  );
}
