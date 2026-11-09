import 'package:flutter/foundation.dart';

import '../../models/catalogue.dart';
import '../../data/bundled_transcripts.dart';
import '../catalogue/catalogue_search.dart';
import '../catalogue/catalogue_words.dart';

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

enum EpisodeFilter { all, numbered, side, transcribed }

enum EpisodeOrder {
  latestFirst('Latest to earliest'),
  earliestFirst('Earliest to latest'),
  titleAscending('A–Z'),
  titleDescending('Z–A');

  const EpisodeOrder(this.label);
  final String label;
}

class EpisodeController extends ChangeNotifier {
  EpisodeController(
    Iterable<Episode> episodes, {
    bool Function(String guid)? hasTranscript,
  }) : episodes = List.unmodifiable(episodes),
       _hasTranscript = hasTranscript;

  final List<Episode> episodes;
  final bool Function(String guid)? _hasTranscript;
  bool Function(String guid) get hasTranscript =>
      _hasTranscript ?? BundledTranscripts.hasEpisode;
  String _query = '';
  String _indexQuery = '';
  List<EpisodeIndexEntry> _indexEntries = [];
  final Map<String, List<String>> _indexMatches = {};
  Set<String>? _transcriptMatches;
  String get query => _query;
  String get indexQuery => _indexQuery;
  bool get showingTranscriptMatches => _transcriptMatches != null;
  List<String> matchingIndexNames(String guid) =>
      List.unmodifiable(_indexMatches[guid] ?? const <String>[]);
  EpisodeFilter _filter = EpisodeFilter.all;
  Episode? _selected;
  final _orders = {
    EpisodeFilter.all: EpisodeOrder.latestFirst,
    EpisodeFilter.numbered: EpisodeOrder.titleAscending,
    EpisodeFilter.side: EpisodeOrder.latestFirst,
    EpisodeFilter.transcribed: EpisodeOrder.latestFirst,
  };

  // Hot reload retains existing controllers and their older sort maps.
  EpisodeOrder get order => _orders[_filter] ?? EpisodeOrder.latestFirst;
  List<EpisodeOrder> get availableOrders => EpisodeOrder.values;

  void setOrder(EpisodeOrder value) {
    if (!availableOrders.contains(value) || order == value) return;
    _orders[_filter] = value;
    notifyListeners();
  }

  EpisodeFilter get filter => _filter;
  Episode? get selected => _selected;

  bool _matchesFilter(Episode episode) => switch (_filter) {
    EpisodeFilter.all => true,
    EpisodeFilter.numbered => !episode.isSideEpisode,
    EpisodeFilter.side => episode.isSideEpisode,
    EpisodeFilter.transcribed => hasTranscript(episode.guid),
  };

  void refreshTranscriptAvailability() => _update();

  List<Episode> get visibleEpisodes {
    final search = CatalogueSearch(_query);
    final visible = episodes
        .where((episode) {
          return _matchesFilter(episode) &&
              search.matchesEpisode(episode) &&
              (_indexQuery.trim().isEmpty ||
                  (_transcriptMatches?.contains(episode.guid) ??
                      _indexMatches.containsKey(episode.guid)));
        })
        .toList(growable: false);
    // List.sort is not stable: retain the input index explicitly for ties.
    final sourceOrder = {
      for (var i = 0; i < episodes.length; i++) episodes[i]: i,
    };
    final sortingByTitle =
        order == EpisodeOrder.titleAscending ||
        order == EpisodeOrder.titleDescending;
    final titleKeys = {
      if (sortingByTitle)
        for (final episode in visible)
          episode: episodeTitleSortKey(episode.title),
    };
    visible.sort((a, b) {
      int comparison;
      if (sortingByTitle) {
        comparison = titleKeys[a]!.compareTo(titleKeys[b]!);
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

  Set<String> get titleFilteredGuids => {
    for (final episode in episodes)
      if (CatalogueSearch(_query).matchesEpisode(episode) &&
          _matchesFilter(episode))
        episode.guid,
  };

  void setIndexQuery(String value) {
    _indexQuery = value;
    _transcriptMatches = null;
    _update();
  }

  void showTranscriptMatches(Iterable<String> guids) {
    _transcriptMatches = guids.toSet();
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
    if (_indexQuery.trim().isNotEmpty) {
      final search = CatalogueSearch(_indexQuery);
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
