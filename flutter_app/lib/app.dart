import 'package:flutter/material.dart';

import 'features/catalogue/catalogue_shell.dart';
import 'services/native_audio_engine.dart';
import 'services/playback_controller.dart';
import 'services/playback_preferences.dart';
import 'widgets/playback_bar.dart';
import 'widgets/playback_route_observer.dart';
import 'widgets/playback_scope.dart';

class CommonDescentApp extends StatefulWidget {
  const CommonDescentApp({super.key});

  @override
  State<CommonDescentApp> createState() => _CommonDescentAppState();
}

class _CommonDescentAppState extends State<CommonDescentApp> {
  late final _playback = PlaybackController(
    createEngine: NativeAudioEngine.new,
    preferenceStore: FilePlaybackPreferenceStore(),
  );

  @override
  void initState() {
    super.initState();
    _playback.initialisePreferences();
  }

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PlaybackScope(
      controller: _playback,
      child: MaterialApp(
        title: 'Common Descent Listing',
        debugShowCheckedModeBanner: false,
        navigatorObservers: [playbackRouteObserver],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF246B62)),
        ),
        home: const CatalogueShell(),
        builder: (context, child) {
          final playback = PlaybackScope.maybeOf(context)!;
          return PlaybackLayout(
            controller: playback,
            showPlayer: playback.output == PlaybackOutput.audioPlayer,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
