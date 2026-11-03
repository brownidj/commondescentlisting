import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'transcript_edits.dart';

typedef TranscriptExporter = Future<String?> Function(
  Map<String, String> files,
);

Map<String, String> transcriptExportFiles(TranscriptEdits edits, String stem) {
  if (!edits.ready || edits.busy) {
    throw StateError('Corrections are not ready.');
  }
  final transcript = edits.current;
  final baseline = edits.baseline;
  final document = baseline.sourceDocument == null
      ? <String, dynamic>{}
      : jsonDecode(jsonEncode(baseline.sourceDocument)) as Map<String, dynamic>;
  document['schema_version'] = 1;
  document['episode_guid'] = transcript.episodeGuid;
  if (transcript.audioIdentity != null) {
    document['audio_identity'] = transcript.audioIdentity;
  }
  document['playback_sync_offset_ms'] = edits.syncOffset.inMilliseconds;
  document['review'] = {
    ...?document['review'] as Map<String, dynamic>?,
    'label': transcript.label,
    'note':
        '${transcript.note} Local edits are recorded separately and have not '
        'been automatically checked against the audio.',
    'local_edits': edits.history.isNotEmpty,
  };
  document['segments'] = transcript.cues
      .map(
        (cue) => {
          'id': cue.id,
          'start_ms': cue.start.inMilliseconds,
          'end_ms': cue.end.inMilliseconds,
          'source_start_ms': cue.revisionStart.inMilliseconds,
          'source_end_ms': cue.revisionEnd.inMilliseconds,
          'text': cue.text,
        },
      )
      .toList();
  final prior = <int, Map<String, dynamic>>{
    for (final change in (document['changes'] as List? ?? []))
      (change as Map<String, dynamic>)['line'] as int: change,
  };
  final baselineText = {for (final cue in baseline.cues) cue.id: cue.text};
  document['changes'] = [
    for (final cue in transcript.cues)
      if (prior.containsKey(cue.id) || cue.text != cue.originalText)
        {
          ...?prior[cue.id],
          'line': cue.id,
          'start_ms': cue.start.inMilliseconds,
          'end_ms': cue.end.inMilliseconds,
          'original_text': cue.originalText,
          'text': cue.text,
          'reviewed_baseline_text': baselineText[cue.id],
          'local_correction': cue.text != baselineText[cue.id],
        },
  ];
  document['unresolved'] ??= [
    for (final cue in transcript.cues)
      for (final note in cue.reviewNotes)
        {
          'lines': [cue.id],
          'reason': note,
        },
  ];
  document['local_revision_history'] = edits.history
      .map((r) => r.toJson())
      .toList();
  final txt = '${transcript.cues.map((cue) => cue.text).join('\n')}\n';
  String stamp(Duration time, String separator) {
    String pad(int value, int count) => value.toString().padLeft(count, '0');
    return '${pad(time.inHours, 2)}:${pad(time.inMinutes % 60, 2)}:'
        '${pad(time.inSeconds % 60, 2)}$separator${pad(time.inMilliseconds % 1000, 3)}';
  }

  final vtt = StringBuffer('WEBVTT\n\n');
  final srt = StringBuffer();
  for (var i = 0; i < transcript.cues.length; i++) {
    final cue = transcript.cues[i];
    final text = cue.text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    vtt.write(
      '${stamp(cue.start, '.')} --> ${stamp(cue.end, '.')}\n$escaped\n\n',
    );
    srt.write(
      '${i + 1}\n${stamp(cue.start, ',')} --> ${stamp(cue.end, ',')}\n$text\n\n',
    );
  }
  final safeStem = stem.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-');
  return {
    '$safeStem.json':
        '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    '$safeStem.txt': txt,
    '$safeStem.vtt': vtt.toString(),
    '$safeStem.srt': srt.toString(),
  };
}

Future<String?> exportTranscriptFiles(Map<String, String> files) async {
  late final Directory folder;
  final temporary = Platform.isIOS;
  if (temporary) {
    folder = await Directory.systemTemp.createTemp('transcript-export-');
  } else {
    final selected = await getDirectoryPath(confirmButtonText: 'Export here');
    if (selected == null) return null;
    folder = await Directory(selected).createTemp('transcript-export-');
  }
  try {
    final paths = <String>[];
    for (final entry in files.entries) {
      final file = File('${folder.path}/${entry.key}');
      await file.writeAsString(entry.value, flush: true);
      paths.add(file.path);
    }
    if (temporary) {
      final shared = await const MethodChannel(
        'common_descent/transcript_export',
      ).invokeMethod<bool>('shareFiles', paths);
      return shared == true ? 'Transcript files shared.' : null;
    }
    return 'Transcript exported to ${folder.path}';
  } catch (_) {
    if (!temporary && await folder.exists()) {
      await folder.delete(recursive: true);
    }
    rethrow;
  } finally {
    try {
      if (temporary && await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } on FileSystemException catch (_) {
      // Temporary cleanup must not report a completed share as a failed export.
    }
  }
}
