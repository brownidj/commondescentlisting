import 'catalogue.dart';

class PlaybackChapter {
  const PlaybackChapter({required this.title, required this.start});
  final String title;
  final Duration start;

  /// Published times only; repeated news-section times produce one marker.
  static List<PlaybackChapter> forEpisode(Episode episode) {
    final markers = <Duration, Set<String>>{};
    void add(Duration? time, String title) {
      if (time == null || time.isNegative) return;
      markers.putIfAbsent(time, () => <String>{}).add(title);
    }

    for (final segment in episode.segments) {
      if (segment.isNews) {
        add(segment.newsStartTime, 'News');
        add(
          segment.startTime,
          segment.title?.trim().isNotEmpty == true
              ? segment.title!.trim()
              : 'News',
        );
      } else {
        final label = segment.label
            ?.replaceFirst(
              RegExp(r'^main discussion\s*[,\-:]?\s*', caseSensitive: false),
              '',
            )
            .trim();
        final title = segment.title?.trim().isNotEmpty == true
            ? segment.title!.trim()
            : segment.type;
        add(
          segment.startTime,
          label == null || label.isEmpty ? title : '$title - $label',
        );
      }
    }
    final times = markers.keys.toList()..sort();
    return List.unmodifiable(
      times.map(
        (time) =>
            PlaybackChapter(title: markers[time]!.join(' / '), start: time),
      ),
    );
  }
}
