import 'package:flutter/foundation.dart';

import '../../models/catalogue.dart';
import '../catalogue/catalogue_search.dart';

typedef NewsEntry = ({Episode episode, Segment segment});

class NewsController extends ChangeNotifier {
  NewsController(Catalogue catalogue) {
    final episodes = {
      for (final episode in catalogue.episodes) episode.guid: episode,
    };
    entries = List.unmodifiable([
      for (final segment in catalogue.segments)
        if (segment.isNews)
          (episode: episodes[segment.guid]!, segment: segment),
    ]);
  }

  late final List<NewsEntry> entries;
  String _query = '';

  List<NewsEntry> get visibleEntries {
    final search = CatalogueSearch(_query);
    return entries
        .where((entry) => search.matchesNews(entry.segment))
        .toList(growable: false);
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }
}
