import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../services/episode_link.dart';
import 'segment_card.dart';
import 'news_summary_text.dart';

class EpisodeDetail extends StatefulWidget {
  const EpisodeDetail({
    required this.episode,
    this.onBack,
    this.selectedSegmentId,
    this.openLink = openEpisodeLink,
    super.key,
  });
  final Episode episode;
  final VoidCallback? onBack;
  final String? selectedSegmentId;
  final EpisodeLinkOpener openLink;

  @override
  State<EpisodeDetail> createState() => _EpisodeDetailState();
}

class _EpisodeDetailState extends State<EpisodeDetail> {
  bool _opening = false;

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
    final summaries = episode.segments
        .map((s) => s.newsRaw)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet();
    final review = episode.segments.any(
      (s) =>
          s.needsReview == true ||
          (s.headlineSplitMethod?.trim().isNotEmpty ?? false),
    );
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
          episode.number == null || episode.number!.trim().isEmpty
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
        const SizedBox(height: 12),
        if (sourceUri != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _opening ? null : () => _openSource(sourceUri),
              icon: const Icon(Icons.open_in_new),
              label: Text(
                _opening ? 'Opening episode page…' : 'Open episode page',
              ),
            ),
          )
        else
          const Text('Episode page unavailable'),
        if (review) ...[
          const SizedBox(height: 16),
          const Text(
            'News headlines were split automatically and may need review. '
            'Check the original summary for context.',
          ),
        ],
        if (summaries.isNotEmpty)
          ExpansionTile(
            maintainState: true,
            key: PageStorageKey('episode-news-summary-${episode.guid}'),
            title: const Text('Original news summary'),
            children: [
              for (final summary in summaries) NewsSummaryText(text: summary),
            ],
          ),
        if (episode.newsCount == 0) ...[
          const SizedBox(height: 12),
          const Text(
            'News is not listed for this episode in the loaded catalogue.',
          ),
        ],
        const SizedBox(height: 20),
        Text('Segments', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final segment in episode.segments)
          SegmentCard(
            segment: segment,
            selected: segment.sessionId == widget.selectedSegmentId,
          ),
      ],
    );
  }
}
