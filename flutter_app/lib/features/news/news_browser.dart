import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../services/episode_link.dart';
import '../../widgets/catalogue_message.dart';
import '../episodes/episode_detail.dart';
import '../episodes/segment_card.dart';
import 'news_controller.dart';

class NewsBrowser extends StatefulWidget {
  const NewsBrowser({
    required this.catalogue,
    this.openLink = openEpisodeLink,
    super.key,
  });
  final Catalogue catalogue;
  final EpisodeLinkOpener openLink;

  @override
  State<NewsBrowser> createState() => _NewsBrowserState();
}

class _NewsBrowserState extends State<NewsBrowser> {
  late NewsController _controller;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = NewsController(widget.catalogue);
  }

  @override
  void didUpdateWidget(covariant NewsBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalogue, widget.catalogue)) {
      _controller.dispose();
      _controller = NewsController(widget.catalogue);
      _search.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  void _open(NewsEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Episode details')),
          body: SafeArea(
            child: EpisodeDetail(
              episode: entry.episode,
              selectedSegmentId: entry.segment.sessionId,
              openLink: widget.openLink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(NewsEntry entry) {
    final segment = entry.segment;
    final title = segment.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    final sectionTime =
        segment.newsStartTime ?? (!hasTitle ? segment.startTime : null);
    return ListTile(
      key: ValueKey('news-${segment.sessionId}'),
      isThreeLine: false,
      title: Text(hasTitle ? title : 'News section'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${segment.episodeNumber == null || segment.episodeNumber!.trim().isEmpty ? 'Side episode' : 'Episode ${segment.episodeNumber}'} • ${segment.episodeTitle}',
          ),
          if (hasTitle && segment.startTime != null)
            Text('Item starts at ${displayTime(segment.startTime!)}')
          else if (hasTitle)
            const Text('Item time unavailable'),
          if (sectionTime != null)
            Text('News section starts at ${displayTime(sectionTime)}'),
          if (segment.needsReview == true ||
              (segment.headlineSplitMethod?.trim().isNotEmpty ?? false))
            const Text(
              'Automatic headline split or incomplete data — check original summary',
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.entries.isEmpty) {
      return const CatalogueMessage(
        icon: Icons.newspaper_outlined,
        title: 'No news listed',
        message: 'The loaded catalogue has no news records.',
      );
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final entries = _controller.visibleEntries;
        return CustomScrollView(
          key: const PageStorageKey('news-list'),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'News',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _search,
                      onChanged: _controller.setQuery,
                      decoration: InputDecoration(
                        labelText: 'Search news',
                        hintText: 'Headline, episode title or number',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'Clear news search',
                          onPressed: () {
                            _search.clear();
                            _controller.setQuery('');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${entries.length} of ${_controller.entries.length} news records • Source order',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Headlines may be split automatically. Open an item to check its original summary.',
                    ),
                  ],
                ),
              ),
            ),
            if (entries.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: CatalogueMessage(
                  icon: Icons.search_off,
                  title: 'No matching news',
                  message: 'Try another headline, episode title or number.',
                ),
              )
            else
              SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) => _tile(entries[index]),
              ),
          ],
        );
      },
    );
  }
}
