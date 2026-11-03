import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/episode_audio.dart';

import '../../models/catalogue.dart';
import '../../models/episode_transcript.dart';
import '../../services/playback_controller.dart';
import '../../services/playback_preferences.dart';
import '../../services/transcript_edits.dart';
import '../../services/transcript_timing_diagnostics.dart';

class TranscriptTimingDialog extends StatefulWidget {
  const TranscriptTimingDialog({
    required this.episode,
    required this.player,
    required this.edits,
    required this.diagnostics,
    this.initialPassageId,
    super.key,
  });

  final Episode episode;
  final PlaybackController player;
  final TranscriptEdits edits;
  final TranscriptTimingDiagnostics diagnostics;
  final int? initialPassageId;

  @override
  State<TranscriptTimingDialog> createState() => _TranscriptTimingDialogState();
}

class _TranscriptTimingDialogState extends State<TranscriptTimingDialog> {
  late final _passage = TextEditingController(
    text:
        (widget.initialPassageId ?? widget.edits.current.cues.firstOrNull?.id)
            ?.toString() ??
        '',
  );
  bool _copied = false;
  double? _seekMs;

  TranscriptCue? get _target {
    final id = int.tryParse(_passage.text.trim());
    for (final cue in widget.edits.current.cues) {
      if (cue.id == id) return cue;
    }
    return null;
  }

  bool get _sameEpisode =>
      widget.player.output == PlaybackOutput.audioPlayer &&
      widget.player.episode?.guid == widget.episode.guid;

  bool get _canMark =>
      _sameEpisode &&
      _target != null &&
      _seekMs == null &&
      widget.edits.ready &&
      !widget.edits.busy &&
      !widget.edits.conflict &&
      widget.player.playing &&
      !widget.player.busy &&
      !widget.player.buffering &&
      widget.player.error == null;

  void _record() {
    if (!_canMark) return;
    final player = widget.player;
    // Read the clock on the click, never from a previous build or the edit cue.
    final audio = player.position;
    final offset = widget.edits.syncOffset;
    final sample = TranscriptTimingSample(
      cue: _target!,
      audioPosition: audio,
      offset: offset,
      highlightedId: widget.edits.current.cueAt(audio + offset)?.id,
      audioDuration: player.duration,
      recordedAt: DateTime.now(),
    );
    setState(() {
      widget.diagnostics.samples.add(sample);
      _copied = false;
    });
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: widget.diagnostics.report(widget.episode.title)),
      );
      if (mounted) setState(() => _copied = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report could not be copied. Try again.'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _passage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.player,
    builder: (context, _) {
      final player = widget.player;
      final offset = widget.edits.syncOffset;
      final adjusted = player.position + offset;
      final highlighted = _sameEpisode
          ? widget.edits.current.cueAt(adjusted)
          : null;
      final target = _target;
      final samples = widget.diagnostics.samples;
      final canControl =
          player.preferencesReady &&
          player.output == PlaybackOutput.audioPlayer &&
          !player.busy &&
          EpisodeAudio.sourceFor(widget.episode) != null;
      final duration = _sameEpisode ? player.duration : null;
      final totalMs = duration?.inMilliseconds ?? 0;
      final differences =
          samples.map((s) => s.rawDifference.inMilliseconds).toList()..sort();
      return AlertDialog(
        title: const Text('Transcript timing diagnostics'),
        content: SizedBox(
          width: 740,
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.episode.title),
                if (widget.edits.baseline.audioIdentity != null)
                  const Text(
                    'Audio edition: fixed recording matched to the aligned transcript.',
                  ),
                const Text(
                  'Select the passage you expect to hear, then press '
                  '“Mark spoken start” as its FIRST words begin. Take samples '
                  'near the beginning, middle and end. Do not press Sync.',
                ),
                const SizedBox(height: 12),
                Text(
                  _sameEpisode
                      ? 'Raw audio: ${diagnosticTime(player.position)}\n'
                            'Saved adjustment: ${diagnosticTime(offset, signed: true)}\n'
                            'Adjusted clock: ${diagnosticTime(adjusted)}\n'
                            'Highlighted: ${highlighted == null ? 'none (timestamp gap)' : 'Passage ${highlighted.id} · ${diagnosticTime(highlighted.start)}–${diagnosticTime(highlighted.end)}'}\n'
                            'State: ${player.busy
                                ? 'busy'
                                : player.buffering
                                ? 'buffering'
                                : player.playing
                                ? 'playing'
                                : 'paused'}'
                      : 'Play this episode in Audio player to see its clocks.',
                ),
                if (player.error != null) Text(player.error!),
                if (duration != null)
                  Text('Audio duration: ${diagnosticTime(duration)}'),
                if (widget.edits.current.cues.isNotEmpty)
                  Text(
                    'Last transcript end: ${diagnosticTime(widget.edits.current.cues.last.end)}',
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: canControl
                      ? () {
                          if (_sameEpisode) {
                            player.toggle();
                          } else {
                            player.playEpisode(widget.episode);
                          }
                        }
                      : null,
                  icon: Icon(
                    _sameEpisode && player.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    _sameEpisode && player.playing
                        ? 'Pause audio'
                        : 'Play audio',
                  ),
                ),
                if (totalMs > 0)
                  Slider(
                    key: const ValueKey('diagnostic-seek'),
                    value:
                        (_seekMs ?? player.position.inMilliseconds.toDouble())
                            .clamp(0, totalMs)
                            .toDouble(),
                    max: totalMs.toDouble(),
                    label: diagnosticTime(
                      Duration(
                        milliseconds:
                            (_seekMs ??
                                    player.position.inMilliseconds.toDouble())
                                .round(),
                      ),
                    ),
                    onChanged: canControl
                        ? (value) => setState(() => _seekMs = value)
                        : null,
                    onChangeEnd: canControl
                        ? (value) async {
                            await player.seek(
                              Duration(milliseconds: value.round()),
                            );
                            if (mounted) setState(() => _seekMs = null);
                          }
                        : null,
                  ),
                TextField(
                  key: const ValueKey('diagnostic-passage'),
                  controller: _passage,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Passage number to measure',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  target == null
                      ? 'Enter a valid passage number.'
                      : 'Passage ${target.id} · stored start ${diagnosticTime(target.start)}\n${target.text}',
                ),
                FilledButton.icon(
                  key: const ValueKey('diagnostic-mark'),
                  onPressed: _canMark ? _record : null,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Mark spoken start'),
                ),
                const Text(
                  'Marking does not seek, pause, edit or change Sync. '
                  'Audio must be playing without buffering. Measurements '
                  'last for this transcript page session; copy the report before leaving.',
                ),
                const Divider(),
                Text(
                  '${samples.length} ${samples.length == 1 ? 'measurement' : 'measurements'}',
                ),
                if (differences.length >= 2)
                  Text(
                    'Raw difference range: ${diagnosticTime(Duration(milliseconds: differences.first), signed: true)} '
                    'to ${diagnosticTime(Duration(milliseconds: differences.last), signed: true)}. '
                    'Compare samples in audio-time order; repeated marks of one passage do not establish drift.',
                  ),
                const Text(
                  'Positive difference: words occur later than their stored time. '
                  'Residual includes the saved adjustment; near zero means aligned. '
                  'Human reaction time affects every mark.',
                ),
                for (final sample in samples.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Passage ${sample.cue.id}: raw difference '
                      '${diagnosticTime(sample.rawDifference, signed: true)}',
                    ),
                    subtitle: Text(
                      'Stored ${diagnosticTime(sample.cue.start)} · '
                      'heard ${diagnosticTime(sample.audioPosition)}\n'
                      'Residual ${diagnosticTime(sample.residual, signed: true)} · '
                      'highlighted ${sample.highlightedId ?? 'none'}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: samples.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy),
            label: Text(_copied ? 'Report copied' : 'Copy report'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
