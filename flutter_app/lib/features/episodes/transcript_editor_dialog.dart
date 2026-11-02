import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../models/episode_transcript.dart';
import '../../services/playback_preferences.dart';
import '../../services/transcript_edits.dart';
import '../../widgets/playback_scope.dart';

class TranscriptEditorDialog extends StatefulWidget {
  const TranscriptEditorDialog({
    required this.episode,
    required this.cue,
    required this.edits,
    super.key,
  });
  final Episode episode;
  final TranscriptCue cue;
  final TranscriptEdits edits;

  @override
  State<TranscriptEditorDialog> createState() => _TranscriptEditorDialogState();
}

class _TranscriptEditorDialogState extends State<TranscriptEditorDialog> {
  late final _text = TextEditingController(
    text: widget.edits.textFor(widget.cue),
  );
  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Passage text cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.edits.save(widget.cue.id, _text.text);
      if (mounted) Navigator.of(context).pop(true);
    } on TranscriptEditConflict {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Saved corrections changed in another editor. Your draft is still here; reload before saving.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'The correction could not be saved. Your draft is still here; try again.';
        });
      }
    }
  }

  Future<void> _reloadCorrections() async {
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    await widget.edits.load();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = widget.edits.loadError;
      if (widget.edits.ready) {
        _notice =
            'Latest saved corrections loaded. Your draft is unchanged; press Save to apply it.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final player = PlaybackScope.maybeOf(context);
    final canPlay =
        player != null &&
        player.preferencesReady &&
        player.output == PlaybackOutput.audioPlayer &&
        !player.busy &&
        widget.episode.audioUri != null;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        scrollable: true,
        title: Text('Edit passage ${widget.cue.id}'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Starts at ${widget.cue.timeLabel} · Timestamps are protected',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: player != null && canPlay
                        ? () => player.playEpisode(
                            widget.episode,
                            from: widget.edits.audioStart(widget.cue),
                          )
                        : null,
                    icon: const Icon(Icons.replay),
                    label: const Text('Replay passage'),
                  ),
                  OutlinedButton.icon(
                    onPressed: player != null && player.playing && !player.busy
                        ? player.toggle
                        : null,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause audio'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Replay starts at this passage. Save or Cancel returns to your '
                'previous listening position and resumes only if audio was '
                'playing when you opened Edit.',
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('transcript-editor-text'),
                controller: _text,
                enabled: !_saving,
                minLines: 5,
                maxLines: 12,
                maxLength: 20000,
                decoration: InputDecoration(
                  labelText: 'Passage text',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
              if (widget.edits.conflict)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _saving ? null : _reloadCorrections,
                    child: const Text('Reload saved corrections; keep draft'),
                  ),
                ),
              if (_notice != null) Text(_notice!),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _text.text = widget.cue.originalText;
                            _error = null;
                          }),
                    child: const Text('Restore original'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _text.text = widget.edits.baseline.cues
                                .firstWhere((cue) => cue.id == widget.cue.id)
                                .text;
                            _error = null;
                          }),
                    child: const Text('Use bundled review'),
                  ),
                ],
              ),
              const Text('Text changes are saved only when you press Save.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving || widget.edits.conflict ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

Future<void> showTranscriptHistory(
  BuildContext context,
  TranscriptEdits edits,
) {
  final history = edits.history.reversed.toList();
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Correction history'),
      content: SizedBox(
        width: 650,
        height: 450,
        child: history.isEmpty
            ? const Center(child: Text('No local corrections yet.'))
            : ListView.builder(
                itemCount: history.length,
                itemBuilder: (_, index) {
                  final revision = history[index];
                  final cue = edits.baseline.cues.firstWhere(
                    (cue) => cue.id == revision.cueId,
                  );
                  return ExpansionTile(
                    title: Text('Passage ${revision.cueId} · ${cue.timeLabel}'),
                    subtitle: Text(revision.date.toLocal().toString()),
                    childrenPadding: const EdgeInsets.all(12),
                    children: [
                      SelectableText(
                        'Before: ${revision.before}\n\nAfter: ${revision.after}',
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
