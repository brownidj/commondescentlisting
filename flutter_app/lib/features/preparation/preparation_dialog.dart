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
      refineChatGPT: choice.refineChatGPT,
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
  const PreparationChoice(
    this.model,
    this.redownload, {
    this.refineChatGPT = true,
  });
  final String model;
  final bool redownload;
  final bool refineChatGPT;
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
  bool _refineChatGPT = true;
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
                  labelText: 'Model',
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
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Refine using ChatGPT'),
                value: _refineChatGPT,
                onChanged: (value) =>
                    setState(() => _refineChatGPT = value ?? false),
              ),
              if (_refineChatGPT) ...[
                const Text(
                  'Runs after external-source enrichment and reviews only unconfirmed items using selected transcript passages sent to OpenAI. Estimated US\$0.10–0.30; limit US\$0.50 per preparation. Adds a few minutes. Suggestions still need review.',
                ),
                if (!widget.info.refinementAvailable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(widget.info.refinementMessage),
                  ),
                const SizedBox(height: 12),
              ],
              if (selected != null)
                Text(
                  PreparationEstimate(
                    selected,
                    widget.info,
                    refineChatGPT: _refineChatGPT,
                  ).label,
                ),
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
                  PreparationChoice(
                    selected.id,
                    _redownload,
                    refineChatGPT: _refineChatGPT,
                  ),
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
              ? job?.enrichmentOnly == true
                    ? 'Updating index'
                    : 'Preparing episode'
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
                Text(
                  job?.enrichmentOnly == true
                      ? 'Index updated. Audio and transcript are unchanged.'
                      : 'Audio, transcript and index are available now. Machine-generated wording and index suggestions need review.',
                ),
              if (job?.indexSummary case final info?)
                Text(
                  'Local index: ${info['entries']} entries · ${info['passages']} passages\nTaxonomy: ${info['categories']['fossil']} · Places: ${info['categories']['place']}\nPapers: ${info['categories']['paper']} · Articles: ${info['categories']['article']} · People: ${info['categories']['author']}\n${info['seconds']} seconds for local indexing',
                ),
              if (job?.refinementSummary case final refinement?) ...[
                if (refinement['state'] == 'completed')
                  Text(
                    'ChatGPT fallback: ${refinement['candidates']} unconfirmed candidates · US\$${(refinement['cost_usd'] as num).toStringAsFixed(3)} · ${refinement['held_for_review']} uncertain suggestions retained',
                  ),
                if (refinement['state'] == 'failed') ...[
                  Text('${refinement['warning']}'),
                  if (refinement['cost_usd'] != null)
                    Text(
                      'Recorded API cost: US\$${(refinement['cost_usd'] as num).toStringAsFixed(3)}',
                    ),
                  if (refinement['cost_usd'] == null &&
                      refinement['possible_billable_request'] == true)
                    Text(
                      'API usage may have been charged; up to US\$${(refinement['reserved_usd'] as num).toStringAsFixed(2)} reserved. No automatic retry.',
                    ),
                ],
                if (refinement['state'] == 'disabled' ||
                    refinement['state'] == 'not_needed')
                  const Text(
                    'No paid API refinement performed; confirmed entries were excluded.',
                  ),
              ],
              if (job?.enrichmentSummary case final enrichment?) ...[
                Text(
                  enrichment['state'] == 'running'
                      ? 'Checking external sources…'
                      : 'External enrichment: ${enrichment['confirmed_external'] ?? 0} confirmed by sources · ${enrichment['enriched'] ?? 0} enriched · ${enrichment['unresolved'] ?? 0} unresolved · ${enrichment['stale'] ?? 0} with stale evidence · ${enrichment['duplicates_merged'] ?? 0} duplicates merged',
                ),
                if (enrichment['state'] == 'partial')
                  const Text(
                    'Some external sources were unavailable or not cached. The usable index has been retained. Retry enrichment without transcription or ChatGPT.',
                  ),
                if (enrichment['warning'] case final String warning)
                  Text(warning),
                if (enrichment['warnings'] case final List<dynamic> warnings)
                  for (final warning in warnings) Text('$warning'),
              ],
              if (job?.exportWarning case final warning?) Text(warning),
              if (job?.error != null) SelectableText(job!.error!),
              if (controller.error != null) Text(controller.error!),
            ],
          ),
        ),
        actions: [
          if (job != null && !job.active && job.enrichmentSummary != null)
            TextButton(
              onPressed: () async {
                try {
                  await controller.retryEnrichment();
                } catch (_) {
                  // The controller reports the error inside this dialog.
                }
              },
              child: const Text('Retry external enrichment'),
            ),
          if (job?.active == true && job?.activated != true)
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
