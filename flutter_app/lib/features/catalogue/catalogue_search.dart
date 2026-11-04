import '../../models/catalogue.dart';

/// One matching policy shared by both catalogues; never changes source order.
class CatalogueSearch {
  CatalogueSearch(String query) : query = query.trim().toLowerCase();
  final String query;

  bool _matches(Iterable<String?> fields) =>
      query.isEmpty ||
      fields.any((field) => field?.toLowerCase().contains(query) ?? false);

  bool matchesIndex(Iterable<String> fields) => _matches(fields);

  bool matchesEpisode(Episode episode) =>
      _matches([episode.title, episode.number]);

  bool matchesNews(Segment segment) =>
      _matches([segment.title, segment.episodeTitle, segment.episodeNumber]);
}
