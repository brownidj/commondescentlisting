import 'package:flutter/foundation.dart';

import '../../models/catalogue.dart';
import '../catalogue/catalogue_search.dart';

typedef NewsEntry = ({Episode episode, Segment segment});

enum NewsOrder {
  headlineAscending('Headline A–Z'),
  headlineDescending('Headline Z–A');

  const NewsOrder(this.label);
  final String label;
}

String newsHeadline(Segment segment) {
  final title = segment.title?.trim();
  return title == null || title.isEmpty ? 'News section' : title;
}

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
  NewsOrder _order = NewsOrder.headlineAscending;
  NewsOrder get order => _order;

  void setOrder(NewsOrder value) {
    if (_order == value) return;
    _order = value;
    notifyListeners();
  }

  List<NewsEntry> get visibleEntries {
    final search = CatalogueSearch(_query);
    final visible = entries
        .where((entry) => search.matchesNews(entry.segment))
        .toList(growable: false);
    final sourceOrder = {
      for (var i = 0; i < entries.length; i++) entries[i].segment: i,
    };
    visible.sort((a, b) {
      var comparison = newsHeadline(a.segment)
          .toLowerCase()
          .compareTo(newsHeadline(b.segment).toLowerCase());
      if (_order == NewsOrder.headlineDescending) comparison = -comparison;
      return comparison != 0
          ? comparison
          : sourceOrder[a.segment]!.compareTo(sourceOrder[b.segment]!);
    });
    return visible;
  }

  void setQuery(String query) {
    _query = query;
    notifyListeners();
  }
}
