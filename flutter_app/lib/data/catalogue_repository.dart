import '../models/catalogue.dart';
import 'catalogue_parser.dart';

/// Asset and future local-file loaders share this boundary.
abstract interface class CatalogueSource {
  String get name;
  Future<String> load();
}

class CatalogueRepository {
  CatalogueRepository({required this.source, CatalogueParser? parser})
    : _parser = parser ?? CatalogueParser();

  final CatalogueSource source;
  final CatalogueParser _parser;

  Future<Catalogue> load() async {
    final data = _parser.parse(await source.load(), sourceName: source.name);
    final groups = <String, List<Segment>>{};
    for (final segment in data.segments) {
      final group = groups.putIfAbsent(segment.guid, () => <Segment>[]);
      if (group.isNotEmpty &&
          (group.first.episodeTitle != segment.episodeTitle ||
              group.first.episodeNumber != segment.episodeNumber ||
              (segment.audioUrl != null &&
                  group.any(
                    (existing) =>
                        existing.audioUrl != null &&
                        existing.audioUrl != segment.audioUrl,
                  )))) {
        throw FormatException(
          '${source.name}: segments[${segment.sourceIndex}] '
          '(record ${segment.sourceIndex + 1}): conflicting episode metadata '
          'for GUID ${segment.guid}',
        );
      }
      group.add(segment);
    }
    return Catalogue(
      podcast: data.podcast,
      segments: data.segments,
      episodes: groups.entries.map(
        (entry) => Episode(
          guid: entry.key,
          title: entry.value.first.episodeTitle,
          number: entry.value.first.episodeNumber,
          segments: entry.value,
        ),
      ),
      sourceName: source.name,
    );
  }
}
