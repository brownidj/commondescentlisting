import 'package:flutter/widgets.dart';

import '../services/playback_controller.dart';

class PlaybackScope extends InheritedNotifier<PlaybackController> {
  const PlaybackScope({
    required PlaybackController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static PlaybackController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackScope>()?.notifier;
}
