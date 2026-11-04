import 'package:flutter/foundation.dart';

import '../../models/catalogue.dart';
import '../catalogue/catalogue_search.dart';

enum EpisodeSearchTarget {
  titles('Episode titles'),
  indexed('Index');

  const EpisodeSearchTarget(this.label);
  final String label;
}

class EpisodeIndexEntry {
  EpisodeIndexEntry({
    required this.name,
    required Iterable<String> terms,
    required Iterable<String> episodeGuids,
  }) : terms = List.unmodifiable(terms),
       episodeGuids = Set.unmodifiable(episodeGuids);
  final String name;
  final List<String> terms;
  final Set<String> episodeGuids;
}

enum EpisodeFilter { all, numbered, side }

enum EpisodeOrder {
  latestFirst('Latest to earliest'),
  earliestFirst('Earliest to latest'),
  titleAscending('Title A–Z'),
  titleDescending('Title Z–A');

  const EpisodeOrder(this.label);
  final String label;
}

class EpisodeController extends ChangeNotifier {
  EpisodeController(Iterable<Episode> episodes)
    : episodes = List.unmodifiable(episodes);

  final List<Episode> episodes;
  String _query = '';
  EpisodeSearchTarget _searchTarget = EpisodeSearchTarget.titles;
  List<EpisodeIndexEntry> _indexEntries = [];
  final Map<String, List<String>> _indexMatches = {};
  EpisodeSearchTarget get searchTarget => _searchTarget;
  String get query => _query;
  List<String> matchingIndexNames(String guid) =>
      List.unmodifiable(_indexMatches[guid] ?? const <String>[]);
  EpisodeFilter _filter = EpisodeFilter.all;
  Episode? _selected;
  final _orders = {
    EpisodeFilter.all: EpisodeOrder.latestFirst,
    EpisodeFilter.numbered: EpisodeOrder.titleAscending,
    EpisodeFilter.side: EpisodeOrder.latestFirst,
  };

  EpisodeOrder get order => _orders[_filter]!;
  List<EpisodeOrder> get availableOrders => _filter == EpisodeFilter.numbered
      ? const [EpisodeOrder.titleAscending, EpisodeOrder.titleDescending]
      : const [EpisodeOrder.latestFirst, EpisodeOrder.earliestFirst];

  void setOrder(EpisodeOrder value) {
    if (!availableOrders.contains(value) || order == value) return;
    _orders[_filter] = value;
    notifyListeners();
  }

  EpisodeFilter get filter => _filter;
  Episode? get selected => _selected;

  List<Episode> get visibleEpisodes {
    final search = CatalogueSearch(_query);
    final visible = episodes
        .where((episode) {
          if (_filter == EpisodeFilter.numbered && episode.isSideEpisode) {
            return false;
          }
          if (_filter == EpisodeFilter.side && !episode.isSideEpisode) {
            return false;
          }
          return _searchTarget == EpisodeSearchTarget.titles
              ? search.matchesEpisode(episode)
              : _query.trim().isEmpty ||
                    _indexMatches.containsKey(episode.guid);
        })
        .toList(growable: false);
    // List.sort is not stable: retain the input index explicitly for ties.
    final sourceOrder = {
      for (var i = 0; i < episodes.length; i++) episodes[i]: i,
    };
    visible.sort((a, b) {
      int comparison;
      if (order == EpisodeOrder.titleAscending ||
          order == EpisodeOrder.titleDescending) {
        comparison = a.title.trim().toLowerCase().compareTo(
          b.title.trim().toLowerCase(),
        );
        if (order == EpisodeOrder.titleDescending) comparison = -comparison;
      } else {
        final first = a.publishedAt;
        final second = b.publishedAt;
        if (first == null || second == null) {
          comparison = first == second ? 0 : (first == null ? 1 : -1);
        } else {
          comparison = first.compareTo(second);
          if (order == EpisodeOrder.latestFirst) comparison = -comparison;
        }
      }
      return comparison != 0
          ? comparison
          : sourceOrder[a]!.compareTo(sourceOrder[b]!);
    });
    return visible;
  }

  void setSearchTarget(EpisodeSearchTarget target) {
    if (_searchTarget == target) return;
    _searchTarget = target;
    _update();
  }

  void setIndexEntries(Iterable<EpisodeIndexEntry> entries) {
    _indexEntries = List.unmodifiable(entries);
    _update();
  }

  void setQuery(String value) {
    _query = value;
    _update();
  }

  void setFilter(EpisodeFilter value) {
    _filter = value;
    _update();
  }

  void _update() {
    _indexMatches.clear();
    if (_searchTarget == EpisodeSearchTarget.indexed &&
        _query.trim().isNotEmpty) {
      final search = CatalogueSearch(_query);
      for (final entry in _indexEntries) {
        if (!search.matchesIndex(entry.terms)) continue;
        for (final guid in entry.episodeGuids) {
          final names = _indexMatches.putIfAbsent(guid, () => []);
          if (!names.contains(entry.name)) names.add(entry.name);
        }
      }
    }
    if (_selected != null &&
        !visibleEpisodes.any((episode) => episode.guid == _selected!.guid)) {
      _selected = null;
    }
    notifyListeners();
  }

  void select(Episode episode) {
    _selected = episode;
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    notifyListeners();
  }
}
