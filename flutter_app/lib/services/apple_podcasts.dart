import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/catalogue.dart';
import 'episode_link.dart';

typedef PodcastDestination = ({Uri uri, bool exact});

/// Apple catalogue snapshot, matched by RSS GUID rather than episode number.
class ApplePodcasts {
  static final Future<Map<String, dynamic>> _episodes = _loadEpisodes();

  static Future<Map<String, dynamic>> _loadEpisodes() async {
    try {
      final text = await rootBundle.loadString(
        'assets/data/apple_podcasts_episodes.json',
      );
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      // A missing snapshot must not prevent browsing or searching Podcasts.
      return {};
    }
  }

  static Future<PodcastDestination> destination(Episode episode) async {
    return destinationFor(episode, await _episodes);
  }

  static PodcastDestination destinationFor(
    Episode episode,
    Map<String, dynamic> episodes,
  ) {
    final id = episodes[episode.guid];
    if (id is String && RegExp(r'^\d+$').hasMatch(id)) {
      return (
        uri: Uri.https('podcasts.apple.com', '/podcast/id1207586509', {
          'i': id,
        }),
        exact: true,
      );
    }
    return (
      uri: Uri.https('podcasts.apple.com', '/us/search', {
        'term': 'The Common Descent Podcast ${episode.title}',
      }),
      exact: false,
    );
  }
}

/// Prefer the installed Apple app; retain a web fallback if it is unavailable.
Future<bool> openApplePodcasts(Uri uri) async {
  try {
    if (await openEpisodeLink(uri.replace(scheme: 'podcasts'))) return true;
  } catch (_) {
    // For example, Podcasts may have been removed on iOS.
  }
  return openEpisodeLink(uri);
}
