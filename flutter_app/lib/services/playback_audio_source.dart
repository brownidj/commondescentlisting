import 'package:just_audio/just_audio.dart';

/// Ask Apple platforms to index the fixed recording precisely before seeking.
/// URL sources keep their existing format detection (including HLS/DASH).
UriAudioSource playbackAudioSource(Uri uri) =>
    uri.scheme == 'asset' ||
        uri.path.endsWith('/audio.opus') ||
        uri.host == '127.0.0.1' ||
        uri.host == 'localhost'
    ? ProgressiveAudioSource(
        uri,
        options: const ProgressiveAudioSourceOptions(
          darwinAssetOptions: DarwinAssetOptions(
            preferPreciseDurationAndTiming: true,
          ),
        ),
      )
    : AudioSource.uri(uri);
