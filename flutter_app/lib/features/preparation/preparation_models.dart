class PreparationModel {
  const PreparationModel({
    required this.id,
    required this.bytes,
    required this.rank,
    required this.available,
    required this.secondsPerAudioHour,
    required this.overheadSecondsPerAudioHour,
    required this.fixedSeconds,
    required this.downloadBytesPerSecond,
  });
  factory PreparationModel.fromJson(Map<String, dynamic> value) =>
      PreparationModel(
        id: value['id'] as String,
        bytes: value['bytes'] as int,
        rank: value['rank'] as int,
        available: value['available'] as bool,
        secondsPerAudioHour:
            (value['transcription_seconds_per_audio_hour'] as num).toDouble(),
        overheadSecondsPerAudioHour:
            (value['overhead_seconds_per_audio_hour'] as num).toDouble(),
        fixedSeconds: (value['fixed_seconds'] as num).toDouble(),
        downloadBytesPerSecond: (value['download_bytes_per_second'] as num)
            .toDouble(),
      );
  final String id;
  final int bytes;
  final int rank;
  final bool available;
  final double secondsPerAudioHour;
  final double overheadSecondsPerAudioHour;
  final double fixedSeconds;
  final double downloadBytesPerSecond;

  String get downloadLabel => available
      ? 'Ready'
      : 'Download ${(bytes / 1000000000).toStringAsFixed(2)} GB';
}

class PreparationEpisode {
  const PreparationEpisode({
    required this.prepared,
    required this.audioSeconds,
    required this.durationEstimated,
    this.model,
    this.sourceAvailable = false,
    this.refinementAvailable = false,
    this.refinementMessage = 'Restart the preparation worker to enable ChatGPT refinement, or turn it off.',
  });
  factory PreparationEpisode.fromJson(Map<String, dynamic> value) =>
      PreparationEpisode(
        prepared: value['prepared'] as bool,
        audioSeconds: (value['audio_seconds'] as num).toDouble(),
        durationEstimated: value['duration_estimated'] as bool,
        model: value['model'] as String?,
        sourceAvailable: value['source_available'] as bool,
        refinementAvailable: value['refinement_available'] as bool? ?? false,
        refinementMessage: value['refinement_message'] as String? ?? 'Restart the preparation worker to enable ChatGPT refinement, or turn it off.',
      );
  final bool prepared;
  final double audioSeconds;
  final bool durationEstimated;
  final String? model;
  final bool sourceAvailable;
  final bool refinementAvailable;
  final String refinementMessage;
}

class PreparationEstimate {
  PreparationEstimate(PreparationModel model, PreparationEpisode episode) {
    final processing =
        episode.audioSeconds /
            3600 *
            (model.secondsPerAudioHour + model.overheadSecondsPerAudioHour) +
        model.fixedSeconds;
    final download = model.available
        ? 0.0
        : model.bytes / model.downloadBytesPerSecond;
    lowMinutes = ((processing * 0.65 + download * 0.5) / 60)
        .ceil()
        .clamp(1, 10000)
        .toInt();
    highMinutes = ((processing * 1.6 + download * 2) / 60)
        .ceil()
        .clamp(lowMinutes, 20000)
        .toInt();
    assumedDuration = episode.durationEstimated;
  }
  late final int lowMinutes;
  late final int highMinutes;
  late final bool assumedDuration;
  String get label =>
      'Estimated $lowMinutes–$highMinutes minutes'
      '${assumedDuration ? ' (assuming a two-hour episode)' : ''}. '
      'Includes encoding, transcription and alignment; downloads and hardware affect this estimate.';
}

class PreparationJob {
  const PreparationJob({
    required this.id,
    required this.guid,
    required this.state,
    required this.stage,
    required this.elapsedSeconds,
    required this.remainingSeconds,
    this.fraction,
    this.error,
    this.title,
    this.indexSummary,
    this.refinementSummary,
  });
  factory PreparationJob.fromJson(Map<String, dynamic> value) => PreparationJob(
    id: value['id'] as String,
    guid: value['guid'] as String,
    state: value['state'] as String,
    stage: value['stage'] as String,
    elapsedSeconds: (value['elapsed_seconds'] as num).toInt(),
    remainingSeconds: (value['remaining_seconds'] as num?)?.toInt(),
    fraction: (value['fraction'] as num?)?.toDouble(),
    error: value['error'] as String?,
    title: value['title'] as String?,
    indexSummary: value['index_summary'] as Map<String, dynamic>?,
    refinementSummary: value['refinement_summary'] as Map<String, dynamic>?,
  );
  final String id;
  final String guid;
  final String state;
  final String stage;
  final int elapsedSeconds;
  final int? remainingSeconds;
  final double? fraction;
  final String? error;
  final String? title;
  final Map<String, dynamic>? indexSummary;
  final Map<String, dynamic>? refinementSummary;
  bool get active => state == 'running' || state == 'cancelling';
}
