import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import 'preparation_controller.dart';
import 'preparation_models.dart';

Future<void> showEpisodePreparation(
  BuildContext context,
  Episode episode,
  PreparationController controller,
) async {
  try {
    if (!controller.connected && !await controller.connect()) {
      if (!context.mounted) return;
      final configure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connect to episode preparation'),
          content: const Text(
            'On your Mac, start scripts/episode_preparation_server.zsh once in Terminal. Then choose the CommonDescentListing project folder to connect. Preparation runs on the Mac while this app shows its progress.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Choose project folder'),
            ),
          ],
        ),
      );
      if (configure != true) return;
      if (!await controller.connect(configure: true)) {
        throw StateError(controller.error ?? 'Could not connect.');
      }
    }
    if (!context.mounted) return;
    if (controller.busy) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PreparationProgressDialog(controller: controller),
      );
      return;
    }
    final info = await controller.backend.inspect(episode.guid);
    final models = await controller.backend.models();
    if (!context.mounted) return;
    if (info.prepared) {
      final again = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Re-prepare episode?'),
          content: Text(
            '${episode.title} has already been prepared. Prepare it again? The current edition stays available until a replacement succeeds.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      );
      if (again != true || !context.mounted) return;
    }
    final choice = await showDialog<PreparationChoice>(
      context: context,
      builder: (_) => PreparationOptionsDialog(
        episode: episode,
        info: info,
        models: models,
      ),
    );
    if (choice == null || !context.mounted) return;
    await controller.prepare(
      guid: episode.guid,
      model: choice.model,
      replace: info.prepared,
      redownload: choice.redownload,
    );
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PreparationProgressDialog(controller: controller),
    );
  } catch (error) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Preparation could not start'),
          content: SelectableText('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}

class PreparationChoice {
  const PreparationChoice(this.model, this.redownload);
  final String model;
  final bool redownload;
}

class PreparationOptionsDialog extends StatefulWidget {
  const PreparationOptionsDialog({
    required this.episode,
    required this.info,
    required this.models,
    super.key,
  });
  final Episode episode;
  final PreparationEpisode info;
  final List<PreparationModel> models;
  @override
  State<PreparationOptionsDialog> createState() =>
      _PreparationOptionsDialogState();
}

class _PreparationOptionsDialogState extends State<PreparationOptionsDialog> {
  bool _redownload = false;
  String? _model;
  int get _currentRank {
    for (final model in widget.models) {
      if (model.id == widget.info.model) return model.rank;
    }
    return widget.info.prepared
        ? widget.models
              .map((model) => model.rank)
              .fold(0, (a, b) => a > b ? a : b)
        : 0;
  }

  List<PreparationModel> get _choices => widget.models
      .where(
        (model) =>
            !widget.info.prepared || _redownload || model.rank > _currentRank,
      )
      .toList();
  @override
  void initState() {
    super.initState();
    _redownload =
        widget.info.prepared &&
        !widget.models.any((model) => model.rank > _currentRank);
    _selectDefault();
  }

  void _selectDefault() {
    final choices = _choices;
    if (_redownload && choices.any((model) => model.id == widget.info.model)) {
      _model = widget.info.model;
      return;
    }
    _model = choices.any((model) => model.id == 'medium.en')
        ? 'medium.en'
        : choices.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    final selected = choices.where((model) => model.id == _model).firstOrNull;
    return AlertDialog(
      title: Text(
        'Prepare ${widget.episode.number == null ? widget.episode.title : 'Episode ${widget.episode.number}'}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.info.prepared) ...[
                Text('Current model: ${widget.info.model ?? 'unknown'}'),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(value: true, label: Text('Redownload')),
                    ButtonSegment(
                      value: false,
                      label: const Text('Use larger model'),
                      enabled: widget.models.any(
                        (model) => model.rank > _currentRank,
                      ),
                    ),
                  ],
                  selected: {_redownload},
                  onSelectionChanged: (value) => setState(() {
                    _redownload = value.single;
                    _selectDefault();
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  _redownload
                      ? 'Download a fresh recording, then encode and transcribe it. Advertising may differ.'
                      : 'Keep the recording and retranscribe with a larger model. Your previous edition and corrections are preserved.',
                ),
              ] else
                const Text(
                  'Choose the transcription model. Audio is retained as 16 kbps Opus.',
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('model-$_redownload'),
                initialValue: _model,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Transcription model',
                  border: OutlineInputBorder(),
                ),
                items: choices
                    .map(
                      (model) => DropdownMenuItem(
                        value: model.id,
                        child: Text('${model.id} — ${model.downloadLabel}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _model = value),
              ),
              const SizedBox(height: 16),
              if (selected != null)
                Text(PreparationEstimate(selected, widget.info).label),
              if (selected?.available == false)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'The model will be downloaded and checksum-verified first. Download progress is shown separately.',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.pop(
                  context,
                  PreparationChoice(selected.id, _redownload),
                ),
          child: const Text('Prepare'),
        ),
      ],
    );
  }
}

class PreparationProgressDialog extends StatelessWidget {
  const PreparationProgressDialog({required this.controller, super.key});
  final PreparationController controller;
  String _time(int seconds) => '${seconds ~/ 60}m ${seconds % 60}s';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final job = controller.job;
      return AlertDialog(
        scrollable: true,
        title: Text(
          job?.active == true
              ? 'Preparing episode'
              : job?.state == 'completed'
              ? 'Episode ready'
              : 'Preparation stopped',
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job?.title != null)
                Text(
                  job!.title!,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              Text(job?.stage ?? 'Starting…'),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: job?.active == true
                    ? job?.fraction
                    : job?.state == 'completed'
                    ? 1
                    : 0,
                semanticsLabel: 'Preparation stage progress',
              ),
              const SizedBox(height: 8),
              if (job?.fraction != null)
                Text('${(job!.fraction! * 100).round()}% of this stage'),
              if (job != null)
                Text(
                  'Elapsed ${_time(job.elapsedSeconds)}${job.remainingSeconds == null || !job.active ? '' : ' • about ${_time(job.remainingSeconds!)} remaining'}',
                ),
              if (job?.state == 'completed')
                const Text(
                  'Audio, transcript and local index are available now. Machine-generated wording and index suggestions need review.',
                ),
              if (job?.indexSummary case final info?)
                Text(
                  'Local index: ${info['entries']} entries · ${info['passages']} passages\nTaxonomy: ${info['categories']['fossil']} · Places: ${info['categories']['place']}\nPapers: ${info['categories']['paper']} · Articles: ${info['categories']['article']} · People: ${info['categories']['author']}\n${info['seconds']} seconds · No paid API calls',
                ),
              if (job?.error != null) SelectableText(job!.error!),
              if (controller.error != null) Text(controller.error!),
            ],
          ),
        ),
        actions: [
          if (job?.active == true)
            TextButton(
              onPressed: job?.state == 'cancelling' ? null : controller.cancel,
              child: const Text('Cancel preparation'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              job?.active == true ? 'Continue in background' : 'Close',
            ),
          ),
        ],
      );
    },
  );
}
