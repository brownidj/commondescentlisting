import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/episode_audio.dart';

import '../../data/bundled_transcripts.dart';
import '../../models/catalogue.dart';
import '../../services/episode_link.dart';
import '../../services/apple_podcasts.dart';
import '../../services/playback_preferences.dart';
import '../../services/playback_controller.dart';
import '../../services/current_transcript.dart';
import '../../services/news_transcript_seek.dart';
import '../../widgets/playback_scope.dart';
import 'segment_card.dart';
import 'news_summary_text.dart';
import 'transcript_page.dart';
import '../preparation/preparation_scope.dart';
import '../preparation/preparation_dialog.dart';

class EpisodeDetail extends StatefulWidget {
  const EpisodeDetail({
    required this.episode,
    this.onBack,
    this.selectedSegmentId,
    this.openLink = openEpisodeLink,
    this.openPodcastLink = openApplePodcasts,
    this.loadPodcastDestination = ApplePodcasts.destination,
    this.loadNewsTranscript = loadCurrentTranscript,
    this.newsTranscriptAvailable = BundledTranscripts.hasEpisode,
    this.newsAudioMatches = currentTranscriptAudioMatches,
    super.key,
  });
  final Future<CurrentTranscript> Function(Episode) loadNewsTranscript;
  final bool Function(String) newsTranscriptAvailable;
  final bool Function(CurrentTranscript) newsAudioMatches;
  final Episode episode;
  final VoidCallback? onBack;
  final String? selectedSegmentId;
  final EpisodeLinkOpener openLink;
  final EpisodeLinkOpener openPodcastLink;
  final Future<PodcastDestination> Function(Episode) loadPodcastDestination;

  @override
  State<EpisodeDetail> createState() => _EpisodeDetailState();
}

class _EpisodeDetailState extends State<EpisodeDetail> {
  bool _opening = false;
  bool _findingNews = false;
  String? _newsPlaybackNote;
  int _newsRequest = 0;
  bool _openingPodcast = false;
  late Future<PodcastDestination> _podcastDestination;
  Episode? _previewedEpisode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _previewEpisode();
  }

  void _previewEpisode() {
    final playback = PlaybackScope.maybeOf(context);
    if (playback == null ||
        !playback.preferencesReady ||
        playback.output != PlaybackOutput.audioPlayer) {
      _previewedEpisode = null;
      return;
    }
    if (identical(_previewedEpisode, widget.episode)) return;
    final selected = widget.episode;
    _previewedEpisode = selected;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.episode, selected)) {
        playback.selectEpisode(selected);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _podcastDestination = widget.loadPodcastDestination(widget.episode);
  }

  @override
  void didUpdateWidget(covariant EpisodeDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode != widget.episode ||
        oldWidget.selectedSegmentId != widget.selectedSegmentId) {
      _newsRequest++;
      _newsPlaybackNote = null;
      _findingNews = false;
    }
    if (oldWidget.episode != widget.episode) {
      _podcastDestination = widget.loadPodcastDestination(widget.episode);
      _previewEpisode();
    }
  }

  Future<void> _openPodcast(Uri uri) async {
    setState(() => _openingPodcast = true);
    var opened = false;
    try {
      opened = await widget.openPodcastLink(uri);
    } catch (_) {
      // External application failures must leave the catalogue usable.
    }
    if (!mounted) return;
    setState(() => _openingPodcast = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apple Podcasts could not be opened.')),
      );
    }
  }

  Future<void> _openSource(Uri uri) async {
    setState(() => _opening = true);
    var opened = false;
    try {
      opened = await widget.openLink(uri);
    } catch (_) {
      // Browser/plugin failures are recoverable; keep the catalogue visible.
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The episode page could not be opened. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _playNewsItem(
    Segment selected,
    PlaybackController player,
  ) async {
    if (_findingNews) {
      return;
    }
    final episode = widget.episode;
    final request = ++_newsRequest;
    setState(() {
      _findingNews = true;
      _newsPlaybackNote = 'Looking for the news item in the transcript…';
    });
    final fallback = selected.startTime ?? newsSectionStart(episode);
    NewsSeekTarget target = NewsSeekTarget(
      time: fallback,
      message:
          'No transcript is available. ${selected.startTime != null ? "Using the published item time." : "Play starts the whole news section, not the selected item."}',
    );
    CurrentTranscript? document;
    try {
      if (widget.newsTranscriptAvailable(episode.guid)) {
        document = await widget.loadNewsTranscript(episode);
        if (!widget.newsAudioMatches(document)) {
          target = NewsSeekTarget(
            time: fallback,
            message: 'Transcript and playback recording do not match. Using the published section/item time; no item match is claimed.',
          );
          document = null;
        } else {
          target = matchNewsPassage(episode, selected, document);
        }
      }
    } catch (_) {
      document = null;
      target = NewsSeekTarget(
        time: fallback,
        message: 'The transcript or saved corrections could not be read. Using the published section/item time; no item match is claimed.',
      );
    }
    if (!mounted ||
        request != _newsRequest ||
        widget.episode != episode ||
        widget.selectedSegmentId != selected.sessionId) {
      return;
    }
    setState(() {
      _findingNews = false;
      _newsPlaybackNote = target.time == null
          ? 'No reliable item or news-section start time is available.'
          : target.message;
    });
    if (target.time == null ||
        !player.preferencesReady ||
        player.output != PlaybackOutput.audioPlayer) {
      return;
    }
    if (document != null) {
      player.setTranscriptContext(document.transcript, document.syncOffset);
    }
    await player.playEpisode(episode, from: target.time);
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final playback = PlaybackScope.maybeOf(context);
    final preparation = PreparationScope.maybeOf(context);
    final newsStart = newsSectionStart(episode);
    final ValueChanged<Duration>? openTime =
        playback != null &&
            playback.preferencesReady &&
            playback.output == PlaybackOutput.audioPlayer &&
            !playback.busy &&
            !_findingNews &&
            EpisodeAudio.sourceFor(episode) != null
        ? (time) => playback.playEpisode(episode, from: time)
        : null;
    Uri? source;
    for (final segment in episode.segments) {
      source = segment.sourceUri;
      if (source != null) break;
    }
    final sourceUri = source;
    Segment? selectedSegment;
    for (final segment in episode.segments) {
      if (segment.sessionId == widget.selectedSegmentId) {
        selectedSegment = segment;
      }
    }
    return ListView(
      // Scroll offsets and expansion flags must never share a storage entry.
      key: PageStorageKey('episode-detail-scroll-${episode.guid}'),
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to episodes'),
            ),
          ),
        Text(
          episode.isSideEpisode ? 'Side episode' : 'Episode ${episode.number}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SelectableText(
          episode.title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text('${episode.newsCount} news records'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<PodcastDestination>(
                        future: _podcastDestination,
                        builder: (context, snapshot) {
                          final useApple =
                              playback?.output == PlaybackOutput.applePodcasts;
                          final destination = snapshot.data;
                          final ready =
                              (playback?.preferencesReady ?? true) &&
                              !_openingPodcast &&
                              !_findingNews &&
                              !(playback?.busy ?? false);
                          final available = useApple
                              ? destination != null
                              : playback != null &&
                                    EpisodeAudio.sourceFor(episode) != null;
                          return IconButton.filled(
                            key: const ValueKey('episode-play'),
                            tooltip: 'Play',
                            onPressed: !ready || !available
                                ? null
                                : useApple
                                ? () => _openPodcast(destination!.uri)
                                : () async {
                                    final requested = selectedSegment;
                                    if (requested == null) {
                                      await playback!.playEpisode(episode);
                                    } else {
                                      await _playNewsItem(requested, playback!);
                                    }
                                  },
                            icon: const Icon(Icons.play_arrow),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      if (sourceUri != null)
                        Tooltip(
                          message:
                              'News headlines were split automatically and may need review. '
                              'Open the episode page for context.',
                          child: OutlinedButton.icon(
                            onPressed: _opening
                                ? null
                                : () => _openSource(sourceUri),
                            icon: const Icon(Icons.open_in_new),
                            label: Text(
                              _opening ? 'Opening episode page…' : 'Episode',
                            ),
                          ),
                        )
                      else
                        const Text('Episode page unavailable'),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (preparation != null &&
                            !kIsWeb &&
                            defaultTargetPlatform == TargetPlatform.macOS &&
                            episode.number != null)
                          Tooltip(
                            message:
                                'Preparing a transcript may take some time. '
                                'Automatic transcription will probably not be 100% accurate.',
                            child: OutlinedButton.icon(
                              onPressed: preparation.connecting
                                  ? null
                                  : () => showEpisodePreparation(
                                      context,
                                      episode,
                                      preparation,
                                    ),
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: Text(
                                preparation.busy
                                    ? 'Preparation progress'
                                    : 'Prepare transcript',
                              ),
                            ),
                          ),
                        if (BundledTranscripts.hasEpisode(episode.guid)) ...[
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TranscriptPage(episode: episode),
                              ),
                            ),
                            icon: const Icon(Icons.article_outlined),
                            label: const Text('Transcript'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (selectedSegment != null) ...[
          const SizedBox(height: 12),
          Semantics(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Opened from news'),
                    Text(
                      'Requested headline: ${selectedSegment.title?.trim().isNotEmpty == true ? selectedSegment.title : 'News section'}',
                    ),
                    Text(
                      'News item ${episode.segments.where((s) => s.isNews).toList().indexWhere((s) => s.sessionId == widget.selectedSegmentId) + 1} '
                      'of ${episode.newsCount}',
                    ),
                    Text(
                      _newsPlaybackNote ??
                          (widget.newsTranscriptAvailable(episode.guid)
                              ? 'Play will look for a transcript match for this headline. The News section control starts the whole section.'
                              : selectedSegment.startTime != null
                              ? 'Play uses the published item time. The News section control starts the whole section.'
                              : 'No transcript is available. Play starts the whole news section, not the selected item.'),
                    ),
                    if (selectedSegment.newsRaw != null)
                      ExpansionTile(
                        maintainState: true,
                        key: PageStorageKey(
                          'selected-news-summary-${selectedSegment.sessionId}',
                        ),
                        title: const Text('Selected item original summary'),
                        children: [
                          NewsSummaryText(text: selectedSegment.newsRaw!),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (episode.newsCount == 0) ...[
          const SizedBox(height: 12),
          const Text(
            'News is not listed for this episode in the loaded catalogue.',
          ),
        ],
        const SizedBox(height: 20),
        Text('Segments', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final segment in episode.segments) ...[
          if (segment.isNews &&
              identical(segment, episode.segments.firstWhere((s) => s.isNews)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('News', style: Theme.of(context).textTheme.titleMedium),
                  if (newsStart != null)
                    if (openTime != null)
                      TextButton.icon(
                        onPressed: () => openTime(newsStart),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          '${selectedSegment == null ? "- starts at" : "- section starts at"} ${displayTime(newsStart)}',
                        ),
                      )
                    else
                      Text('- starts at ${displayTime(newsStart)}'),
                ],
              ),
            ),
          if (segment.type == 'Main Discussion' &&
              identical(
                segment,
                episode.segments.firstWhere((s) => s.type == 'Main Discussion'),
              ))
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Main discussion',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          SegmentCard(
            segment: segment,
            // A browsing selection is not evidence of the audio item playing.
            selected: false,
            onOpenTime: openTime,
          ),
        ],
      ],
    );
  }
}
