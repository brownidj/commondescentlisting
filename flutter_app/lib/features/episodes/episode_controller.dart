import 'package:flutter/foundation.dart';

import '../../models/catalogue.dart';
import '../catalogue/catalogue_search.dart';

enum EpisodeFilter { all, numbered, side }

class EpisodeController extends ChangeNotifier {
  EpisodeController(Iterable<Episode> episodes)
    : episodes = List.unmodifiable(episodes);

  final List<Episode> episodes;
  String _query = '';
  EpisodeFilter _filter = EpisodeFilter.all;
  Episode? _selected;

  EpisodeFilter get filter => _filter;
  Episode? get selected => _selected;

  List<Episode> get visibleEpisodes {
    final search = CatalogueSearch(_query);
    return episodes
        .where((episode) {
          if (_filter == EpisodeFilter.numbered && episode.isSideEpisode) {
            return false;
          }
          if (_filter == EpisodeFilter.side && !episode.isSideEpisode) {
            return false;
          }
          return search.matchesEpisode(episode);
        })
        .toList(growable: false);
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
