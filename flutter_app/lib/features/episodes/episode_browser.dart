import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../services/episode_link.dart';
import '../../widgets/catalogue_message.dart';
import 'episode_controller.dart';
import 'episode_detail.dart';

class EpisodeBrowser extends StatefulWidget {
  const EpisodeBrowser({
    required this.catalogue,
    this.openLink = openEpisodeLink,
    super.key,
  });
  final Catalogue catalogue;
  final EpisodeLinkOpener openLink;

  @override
  State<EpisodeBrowser> createState() => _EpisodeBrowserState();
}

class _EpisodeBrowserState extends State<EpisodeBrowser> {
  late EpisodeController _controller;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = EpisodeController(widget.catalogue.episodes);
  }

  @override
  void didUpdateWidget(covariant EpisodeBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalogue, widget.catalogue)) {
      _controller.dispose();
      _controller = EpisodeController(widget.catalogue.episodes);
      _search.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  Widget _list() {
    final episodes = _controller.visibleEpisodes;
    return CustomScrollView(
      key: const PageStorageKey('episode-list'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Episodes',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: _controller.setQuery,
                  decoration: InputDecoration(
                    labelText: 'Search episodes',
                    hintText: 'Title or episode number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear search',
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in EpisodeFilter.values)
                      ChoiceChip(
                        label: Text(switch (filter) {
                          EpisodeFilter.all => 'All',
                          EpisodeFilter.numbered => 'Numbered',
                          EpisodeFilter.side => 'Side episodes',
                        }),
                        selected: _controller.filter == filter,
                        onSelected: (_) => _controller.setFilter(filter),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${episodes.length} of ${widget.catalogue.episodes.length} episodes • Source order',
                ),
              ],
            ),
          ),
        ),
        if (episodes.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: CatalogueMessage(
              icon: Icons.search_off,
              title: 'No matching episodes',
              message: 'Try another search or choose a different filter.',
            ),
          )
        else
          SliverList.builder(
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              return ListTile(
                key: ValueKey('episode-${episode.guid}'),
                selected: _controller.selected?.guid == episode.guid,
                title: Text(episode.title),
                subtitle: Text(
                  '${episode.number == null || episode.number!.trim().isEmpty ? 'Side episode' : 'Episode ${episode.number}'} • '
                  '${episode.newsCount} listed news records',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _controller.select(episode),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.catalogue.episodes.isEmpty) {
      return const CatalogueMessage(
        icon: Icons.library_books_outlined,
        title: 'The catalogue is empty',
        message: 'No episodes are listed in the loaded YAML.',
      );
    }
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final selected = _controller.selected;
          final detail = selected == null
              ? const CatalogueMessage(
                  icon: Icons.library_books_outlined,
                  title: 'Choose an episode',
                  message: 'Select an episode to see its news and discussion segments.',
                )
              : EpisodeDetail(
                  key: ValueKey(selected.guid),
                  episode: selected,
                  openLink: widget.openLink,
                  onBack: wide ? null : _controller.clearSelection,
                );
          if (!wide) return selected == null ? _list() : detail;
          return Row(
            children: [
              SizedBox(width: 340, child: _list()),
              const VerticalDivider(width: 1),
              Expanded(child: detail),
            ],
          );
        },
      ),
    );
  }
}
