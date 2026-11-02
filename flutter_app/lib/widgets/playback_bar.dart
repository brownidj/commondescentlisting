import 'package:flutter/material.dart';

import '../features/episodes/segment_card.dart';
import '../models/playback_chapter.dart';
import '../services/playback_controller.dart';
import 'playback_keyboard_controls.dart';

/// Both the Navigator and persistent controls need overlay-backed tooltips.
class PlaybackLayout extends StatelessWidget {
  const PlaybackLayout({
    required this.controller,
    required this.child,
    this.showPlayer = true,
    super.key,
  });
  final PlaybackController controller;
  final Widget child;
  final bool showPlayer;

  @override
  Widget build(BuildContext context) => PlaybackKeyboardControls(
    controller: controller,
    enabled: showPlayer,
    child: Overlay.wrap(
      child: Column(
        children: [
          Expanded(child: child),
          if (showPlayer) PlaybackBar(controller: controller),
        ],
      ),
    ),
  );
}

class PlaybackBar extends StatefulWidget {
  const PlaybackBar({required this.controller, super.key});
  final PlaybackController controller;

  @override
  State<PlaybackBar> createState() => _PlaybackBarState();
}

class _PlaybackBarState extends State<PlaybackBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final player = widget.controller;
        final episode = player.episode;
        final chapters = episode == null
            ? const <PlaybackChapter>[]
            : PlaybackChapter.forEpisode(episode);
        final canPlay = episode?.audioUri != null && !player.busy;
        final edit = player.transcriptEditAction;
        final passage = player.currentPassage;
        PlaybackChapter? activeChapter;
        for (final chapter in chapters) {
          if (chapter.start <= player.position) activeChapter = chapter;
        }
        final total = player.duration?.inMilliseconds.toDouble() ?? 0.0;
        final position = (_drag ?? player.position.inMilliseconds.toDouble())
            .clamp(0.0, total > 0 ? total : 1.0)
            .toDouble();
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          episode?.title ?? 'Select an episode to play',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close player',
                        onPressed: player.busy || episode == null
                            ? null
                            : player.close,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  if (player.buffering)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Loading audio',
                    ),
                  if (player.error != null)
                    Text(
                      player.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back 15 seconds',
                        onPressed: !canPlay
                            ? null
                            : () => player.skip(const Duration(seconds: -15)),
                        icon: const Icon(Icons.replay),
                      ),
                      IconButton(
                        tooltip: player.playing ? 'Pause' : 'Play',
                        onPressed: canPlay ? player.toggle : null,
                        icon: Icon(
                          player.playing ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Forward 30 seconds',
                        onPressed: !canPlay
                            ? null
                            : () => player.skip(const Duration(seconds: 30)),
                        icon: const Icon(Icons.forward_30),
                      ),
                      Expanded(
                        child: Slider(
                          label: displayTime(
                            Duration(milliseconds: position.round()),
                          ),
                          value: position,
                          max: total > 0 ? total : 1.0,
                          onChanged: player.busy || total <= 0
                              ? null
                              : (value) => setState(() => _drag = value),
                          onChangeEnd: (value) {
                            setState(() => _drag = null);
                            player.seek(Duration(milliseconds: value.round()));
                          },
                        ),
                      ),
                    ],
                  ),
                  Text(
                    passage != null
                        ? 'Passage ${passage.id} of ${player.transcriptPassageCount}'
                        : episode == null
                        ? 'No passage selected'
                        : player.transcriptPassageCount == null
                        ? 'Transcript passage unavailable'
                        : 'Between transcript passages',
                    key: const ValueKey('player-current-passage'),
                  ),
                  if (chapters.isNotEmpty || edit != null)
                    Row(
                      children: [
                        Expanded(
                          child: chapters.isEmpty
                              ? const Text('No segment times listed')
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final chapter in chapters)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                            top: 4,
                                          ),
                                          child: Tooltip(
                                            message:
                                                'Jump to ${chapter.title} at ${displayTime(chapter.start)}',
                                            child: ChoiceChip(
                                              label: Text(chapter.title),
                                              selected: identical(
                                                chapter,
                                                activeChapter,
                                              ),
                                              onSelected:
                                                  !canPlay ||
                                                      player.error != null ||
                                                      episode == null
                                                  ? null
                                                  : (_) => player.playEpisode(
                                                      episode,
                                                      from: chapter.start,
                                                    ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                        if (edit != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Edit highlighted passage',
                            key: const ValueKey('player-transcript-edit'),
                            onPressed:
                                player.busy ||
                                    episode?.guid != edit.guid ||
                                    !edit.available()
                                ? null
                                : edit.open,
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        ],
                      ],
                    )
                  else if (episode != null)
                    const Text('No segment times listed'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
