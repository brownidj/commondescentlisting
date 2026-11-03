import 'package:flutter/material.dart';

import '../services/playback_controller.dart';
import 'library_server_settings.dart';
import '../services/playback_preferences.dart';

class PlaybackSettingsDialog extends StatelessWidget {
  const PlaybackSettingsDialog({
    required this.controller,
    this.onLibraryCatalogue,
    super.key,
  });
  final PlaybackController controller;
  final Future<void> Function(String)? onLibraryCatalogue;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Play episodes using'),
              RadioGroup<PlaybackOutput>(
                groupValue: controller.output,
                onChanged: (value) {
                  if (value != null &&
                      !controller.busy &&
                      controller.preferencesReady) {
                    controller.setOutput(value);
                  }
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<PlaybackOutput>(
                      value: PlaybackOutput.audioPlayer,
                      enabled: controller.preferencesReady && !controller.busy,
                      title: const Text('Audio player'),
                      subtitle: const Text('Play here with segment controls.'),
                    ),
                    RadioListTile<PlaybackOutput>(
                      value: PlaybackOutput.applePodcasts,
                      enabled: controller.preferencesReady && !controller.busy,
                      title: const Text('Apple Podcasts'),
                      subtitle: const Text(
                        'Open episodes in the Podcasts app.',
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Changing player stops current audio. Segment seeking is available with Audio player.',
              ),
              if (onLibraryCatalogue != null)
                LibraryServerSettings(onCatalogue: onLibraryCatalogue!),
              if (!controller.preferencesReady || controller.busy)
                const LinearProgressIndicator(),
              if (controller.preferencesError != null)
                Text(controller.preferencesError!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
