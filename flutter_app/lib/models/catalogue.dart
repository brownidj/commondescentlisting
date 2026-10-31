/// Immutable data from the legacy v1 (unversioned) segment YAML contract.
class Podcast {
  const Podcast({required this.title, this.rss});
  final String title;
  final String? rss;
}

class Segment {
  const Segment({
    required this.sourceIndex,
    required this.guid,
    required this.episodeTitle,
    required this.type,
    this.episodeNumber,
    this.title,
    this.label,
    this.sourceUrl,
    this.startTime,
    this.newsStartTime,
    this.newsRaw,
    this.needsReview,
    this.headlineSplitMethod,
  });

  /// Zero-based index in the source list; stable only within that snapshot.
  final int sourceIndex;
  final String guid;
  final String episodeTitle;
  final String? episodeNumber;
  final String type;
  final String? title;
  final String? label;
  final String? sourceUrl;
  final Duration? startTime;
  final Duration? newsStartTime;
  final String? newsRaw;
  final bool? needsReview;
  final String? headlineSplitMethod;

  String get sessionId => '$guid::$sourceIndex';
  bool get isNews => type == 'News';

  /// Unsafe/invalid links remain data, never an actionable browser URL.
  Uri? get sourceUri {
    final uri = Uri.tryParse(sourceUrl ?? '');
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}

class Episode {
  Episode({
    required this.guid,
    required this.title,
    required this.number,
    required Iterable<Segment> segments,
  }) : segments = List.unmodifiable(segments);

  final String guid;
  final String title;
  final String? number;
  final List<Segment> segments;
  int get newsCount => segments.where((segment) => segment.isNews).length;
}

class CatalogueData {
  CatalogueData({required this.podcast, required Iterable<Segment> segments})
    : segments = List.unmodifiable(segments);
  final Podcast podcast;
  final List<Segment> segments;
}

class Catalogue {
  Catalogue({
    required this.podcast,
    required Iterable<Segment> segments,
    required Iterable<Episode> episodes,
    required this.sourceName,
  }) : segments = List.unmodifiable(segments),
       episodes = List.unmodifiable(episodes);

  final Podcast podcast;
  final List<Segment> segments;
  final List<Episode> episodes;
  final String sourceName;
  int get newsCount => segments.where((segment) => segment.isNews).length;
}
