import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/catalogue.dart';
import '../../data/bundled_transcripts.dart';
import '../../data/local_prepared_episodes.dart';
import '../../services/episode_link.dart';
import '../../widgets/catalogue_message.dart';
import '../indexes/index_controller.dart';
import '../indexes/index_models.dart';
import 'episode_controller.dart';
import 'episode_detail.dart';
import 'episode_search_dialogs.dart';

class EpisodeBrowser extends StatefulWidget {
  const EpisodeBrowser({
    required this.catalogue,
    this.openLink = openEpisodeLink,
    this.indexController,
    this.active = true,
    super.key,
  });
  final Catalogue catalogue;
  final EpisodeLinkOpener openLink;
  final KnowledgeIndexController? indexController;
  final bool active;

  @override
  State<EpisodeBrowser> createState() => _EpisodeBrowserState();
}

class _EpisodeBrowserState extends State<EpisodeBrowser>
    with WidgetsBindingObserver {
  late EpisodeController _controller;
  late KnowledgeIndexController _knowledge;
  bool _indexSyncPending = false;
  final _search = TextEditingController();
  final _transcriptSearch = TextEditingController();
  Timer? _searchTimer;
  String? _promptedSearch;
  bool _searchDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = EpisodeController(widget.catalogue.episodes);
    WidgetsBinding.instance.addObserver(this);
    LocalPreparedEpisodes.changes.addListener(_libraryChanged);
    _attachIndex();
  }

  void _attachIndex() {
    _knowledge =
        widget.indexController ??
        KnowledgeIndexController(catalogue: widget.catalogue);
    _knowledge.addListener(_indexChanged);
    _indexChanged();
  }

  void _indexChanged() {
    if (_indexSyncPending) return;
    _indexSyncPending = true;
    // Shared index notifications may arrive while the sibling tab is building.
    scheduleMicrotask(() {
      _indexSyncPending = false;
      if (!mounted) return;
      final byId = {
        for (final e in _knowledge.entities)
          if (!e.deleted && e.review != IndexReview.rejected) e.id: e,
      };
      _controller.setIndexEntries([
        for (final entry in _knowledge.entities)
          if (!entry.deleted && entry.review != IndexReview.rejected)
            EpisodeIndexEntry(
              name: entry.name,
              terms: [
                entry.name,
                ...entry.aliases,
                entry.publication,
                entry.doi,
                for (final id in entry.authorIds)
                  if (byId[id] != null) byId[id]!.name,
              ],
              episodeGuids: (_knowledge.occurrences[entry.id] ?? []).map(
                (occurrence) => occurrence.document.episode.guid,
              ),
            ),
      ]);
      _scheduleFallback();
    });
  }

  void _libraryChanged() {
    if (_controller.indexQuery.trim().isNotEmpty) {
      _controller.setIndexQuery(_controller.indexQuery);
      _promptedSearch = null;
      unawaited(_knowledge.refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _libraryChanged();
  }

  String get _searchKey =>
      '${_controller.query}\u0000${_controller.indexQuery}\u0000${_controller.filter.name}';

  void _scheduleFallback() {
    _searchTimer?.cancel();
    if (!widget.active ||
        _controller.indexQuery.trim().isEmpty ||
        _searchDialogOpen) {
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 700), _checkFallback);
  }

  void _setIndexQuery(String query) {
    _controller.setIndexQuery(query);
    _promptedSearch = null;
    if (query.trim().isNotEmpty &&
        (!_knowledge.ready || _knowledge.error != null) &&
        !_knowledge.busy) {
      unawaited(_knowledge.refresh());
    }
    _scheduleFallback();
  }

  Future<void> _checkFallback() async {
    if (!mounted ||
        !widget.active ||
        _searchDialogOpen ||
        !_knowledge.ready ||
        _knowledge.busy ||
        _knowledge.error != null ||
        _controller.indexQuery.trim().isEmpty ||
        _controller.visibleEpisodes.isNotEmpty ||
        _promptedSearch == _searchKey) {
      return;
    }
    final key = _searchKey;
    _promptedSearch = key;
    _searchDialogOpen = true;
    try {
      await offerEpisodeTranscriptSearch(
        context: context,
        query: _controller.indexQuery.trim(),
        knowledge: _knowledge,
        episodeGuids: _controller.titleFilteredGuids,
        isCurrent: () => mounted && widget.active && _searchKey == key,
        onResults: _controller.showTranscriptMatches,
      );
    } finally {
      _searchDialogOpen = false;
      if (mounted && _searchKey != key) {
        _scheduleFallback();
      }
    }
  }

  @override
  void didUpdateWidget(covariant EpisodeBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _searchTimer?.cancel();
    } else if (!oldWidget.active) {
      _scheduleFallback();
    }
    if (!identical(oldWidget.catalogue, widget.catalogue)) {
      _controller.dispose();
      _controller = EpisodeController(widget.catalogue.episodes);
      _search.clear();
      _transcriptSearch.clear();
      _promptedSearch = null;
    }
    if (!identical(oldWidget.catalogue, widget.catalogue) ||
        oldWidget.indexController != widget.indexController) {
      _knowledge.removeListener(_indexChanged);
      if (oldWidget.indexController == null) _knowledge.dispose();
      _attachIndex();
      if (_controller.indexQuery.trim().isNotEmpty) {
        unawaited(_knowledge.refresh());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalPreparedEpisodes.changes.removeListener(_libraryChanged);
    _knowledge.removeListener(_indexChanged);
    if (widget.indexController == null) _knowledge.dispose();
    _controller.dispose();
    _search.dispose();
    _transcriptSearch.dispose();
    _searchTimer?.cancel();
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
                TextField(
                  key: const ValueKey('episode-title-search'),
                  controller: _search,
                  onChanged: (value) {
                    _controller.setQuery(value);
                    _scheduleFallback();
                  },
                  decoration: InputDecoration(
                    labelText: 'Search episodes',
                    hintText: 'Title or episode number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Clear episode search',
                      onPressed: () {
                        _search.clear();
                        _controller.setQuery('');
                        _scheduleFallback();
                      },
                      icon: const Icon(Icons.clear),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Tooltip(
                  message: 'Searches indexes first',
                  child: TextField(
                    key: const ValueKey('episode-transcript-search'),
                    controller: _transcriptSearch,
                    onChanged: _setIndexQuery,
                    onSubmitted: (_) {
                      _promptedSearch = null;
                      _checkFallback();
                    },
                    decoration: InputDecoration(
                      labelText: 'Search in transcripts',
                      hintText: 'Indexed name, alias, author or reference',
                      prefixIcon: const Icon(Icons.manage_search),
                      suffixIcon: IconButton(
                        tooltip: 'Clear transcript search',
                        onPressed: () {
                          _transcriptSearch.clear();
                          _setIndexQuery('');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_controller.indexQuery.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  if (_knowledge.busy) ...[
                    const LinearProgressIndicator(
                      semanticsLabel: 'Loading episode index search',
                    ),
                    const Text('Loading index…'),
                  ] else if (_knowledge.error != null) ...[
                    Text('Index search could not load. ${_knowledge.error}'),
                    TextButton(
                      onPressed: _knowledge.refresh,
                      child: const Text('Retry index search'),
                    ),
                  ] else
                    Text(
                      _controller.showingTranscriptMatches
                          ? 'Showing direct transcript text matches.'
                          : 'Searches indexed names and aliases across all categories in ${_knowledge.documents.length} available transcripts.',
                    ),
                  if (_knowledge.loadFailures.isNotEmpty)
                    Text(
                      '${_knowledge.loadFailures.length} transcripts could not be loaded; results may be incomplete.',
                    ),
                ],
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in EpisodeFilter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            tooltip: switch (filter) {
                              EpisodeFilter.all => 'All episodes',
                              EpisodeFilter.numbered =>
                                'Main numbered episodes',
                              EpisodeFilter.side => 'Side episodes',
                            },
                            label: Text(switch (filter) {
                              EpisodeFilter.all => 'All',
                              EpisodeFilter.numbered => 'Main',
                              EpisodeFilter.side => 'Side',
                            }),
                            selected: _controller.filter == filter,
                            onSelected: (_) {
                              _controller.setFilter(filter);
                              _scheduleFallback();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EpisodeOrder>(
                  key: ValueKey('episode-order-${_controller.filter.name}'),
                  initialValue: _controller.order,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sort episodes',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final order in _controller.availableOrders)
                      DropdownMenuItem(value: order, child: Text(order.label)),
                  ],
                  onChanged: (order) {
                    if (order != null) _controller.setOrder(order);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '${episodes.length} of ${widget.catalogue.episodes.length} '
                  '${widget.catalogue.episodes.length == 1 ? 'episode' : 'episodes'}',
                ),
              ],
            ),
          ),
        ),
        if (episodes.isEmpty &&
            _controller.indexQuery.trim().isNotEmpty &&
            _knowledge.busy)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: CatalogueMessage(
              icon: Icons.manage_search,
              title: 'Loading index',
              message: 'Finding matches in available transcripts.',
            ),
          )
        else if (episodes.isEmpty &&
            _controller.indexQuery.trim().isNotEmpty &&
            _knowledge.error != null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: CatalogueMessage(
              icon: Icons.error_outline,
              title: 'Index search unavailable',
              message: 'Retry loading the index, or search episode titles.',
            ),
          )
        else if (episodes.isEmpty)
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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${episode.isSideEpisode ? 'Side episode' : 'Episode ${episode.number}'} • ${episode.newsCount} news records',
                    ),
                    if (_controller.indexQuery.trim().isNotEmpty)
                      Text(
                        _controller.showingTranscriptMatches
                            ? 'Transcript text match'
                            : 'Index: ${_controller.matchingIndexNames(episode.guid).take(3).join("; ")}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (BundledTranscripts.hasEpisode(episode.guid)) ...[
                      const Tooltip(
                        message: 'Transcript available',
                        child: Icon(Icons.article_outlined, size: 18),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Icon(Icons.chevron_right),
                  ],
                ),
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
      listenable: Listenable.merge([
        _controller,
        LocalPreparedEpisodes.changes,
      ]),
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
