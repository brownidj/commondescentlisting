import 'package:flutter/services.dart';

import '../models/episode_transcript.dart';

class BundledTranscripts {
  static const episode208Guid =
      'commondescentpodcast.podbean.com/870afb21-277f-398e-ba55-6e50d68ceda6';

  static const _assets = {
    episode208Guid: 'assets/transcripts/episode-208-karoo-reviewed.json',
  };

  static bool hasEpisode(String guid) => _assets.containsKey(guid);

  static Future<EpisodeTranscript> load(String guid) async {
    final asset = _assets[guid];
    if (asset == null) {
      throw const FormatException('No reviewed transcript for this episode.');
    }
    return EpisodeTranscript.parse(
      await rootBundle.loadString(asset),
      episodeGuid: guid,
    );
  }
}
