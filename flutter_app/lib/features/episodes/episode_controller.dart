import 'package:flutter/foundation.dart';

import '../../models/catalogue.dart';

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
    final query = _query.trim().toLowerCase();
    return episodes
        .where((episode) {
          final numbered = episode.number?.trim().isNotEmpty ?? false;
          if (_filter == EpisodeFilter.numbered && !numbered) return false;
          if (_filter == EpisodeFilter.side && numbered) return false;
          return query.isEmpty ||
              episode.title.toLowerCase().contains(query) ||
              (episode.number?.toLowerCase().contains(query) ?? false);
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
