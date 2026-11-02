import 'package:flutter/material.dart';

import '../../data/bundled_transcripts.dart';
import '../../models/catalogue.dart';
import '../../services/episode_link.dart';
import '../../services/apple_podcasts.dart';
import '../../services/playback_preferences.dart';
import '../../widgets/playback_scope.dart';
import 'segment_card.dart';
import 'news_summary_text.dart';
import 'transcript_page.dart';

class EpisodeDetail extends StatefulWidget {
  const EpisodeDetail({
    required this.episode,
    this.onBack,
    this.selectedSegmentId,
    this.openLink = openEpisodeLink,
    this.openPodcastLink = openApplePodcasts,
    this.loadPodcastDestination = ApplePodcasts.destination,
    super.key,
  });
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

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final playback = PlaybackScope.maybeOf(context);
    final review = episode.hasReviewNotice;
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
          episode.isSideEpisode
              ? 'Side episode'
              : 'Episode ${episode.number}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        SelectableText(
          episode.title,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text('${episode.newsCount} listed news records'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
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
                    !(playback?.busy ?? false);
                final available = useApple
                    ? destination != null
                    : playback != null && episode.audioUri != null;
                return FilledButton.icon(
                  onPressed: !ready || !available
                      ? null
                      : useApple
                      ? () => _openPodcast(destination!.uri)
                      : () => playback!.playEpisode(episode),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                );
              },
            ),
            if (sourceUri != null)
              OutlinedButton.icon(
                onPressed: _opening ? null : () => _openSource(sourceUri),
                icon: const Icon(Icons.open_in_new),
                label: Text(
                  _opening ? 'Opening episode page…' : 'Open episode page',
                ),
              )
            else
              const Text('Episode page unavailable'),
            if (BundledTranscripts.hasEpisode(episode.guid))
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TranscriptPage(episode: episode),
                  ),
                ),
                icon: const Icon(Icons.article_outlined),
                label: const Text('Read transcript'),
              ),
          ],
        ),
        if (selectedSegment != null) ...[
          const SizedBox(height: 12),
          Semantics(
            selected: true,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Opened from news'),
                    Text(
                      'Selected headline: ${selectedSegment.title?.trim().isNotEmpty == true ? selectedSegment.title : 'News section'}',
                    ),
                    Text(
                      'News item ${episode.segments.where((s) => s.isNews).toList().indexWhere((s) => s.sessionId == widget.selectedSegmentId) + 1} '
                      'of ${episode.newsCount}',
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
        if (review) ...[
          const SizedBox(height: 16),
          const Text(
            'News headlines were split automatically and may need review. '
            'Open the episode page for context.',
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
              child: Text(
                'News',
                style: Theme.of(context).textTheme.titleMedium,
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
            selected: segment.sessionId == widget.selectedSegmentId,
            onOpenTime:
                playback != null &&
                    playback.preferencesReady &&
                    playback.output == PlaybackOutput.audioPlayer &&
                    !playback.busy &&
                    episode.audioUri != null
                ? (time) => playback.playEpisode(episode, from: time)
                : null,
          ),
        ],
      ],
    );
  }
}
