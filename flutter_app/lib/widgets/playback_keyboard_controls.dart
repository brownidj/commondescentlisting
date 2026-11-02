import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/playback_controller.dart';
import '../services/playback_preferences.dart';

class PlaybackKeyboardControls extends StatefulWidget {
  const PlaybackKeyboardControls({
    required this.controller,
    required this.enabled,
    required this.child,
    super.key,
  });
  final PlaybackController controller;
  final bool enabled;
  final Widget child;

  @override
  State<PlaybackKeyboardControls> createState() =>
      _PlaybackKeyboardControlsState();
}

class _PlaybackKeyboardControlsState extends State<PlaybackKeyboardControls> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  bool _handleKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!widget.enabled ||
        event.logicalKey != LogicalKeyboardKey.space ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed) {
      return false;
    }
    final focusNode = FocusManager.instance.primaryFocus;
    final focusContext = focusNode?.context;
    if (focusNode != null && focusNode is! FocusScopeNode) return false;
    if (focusContext != null) {
      final route = ModalRoute.of(focusContext);
      if (route is PopupRoute<dynamic> || route?.isCurrent == false) {
        return false;
      }
    }
    final player = widget.controller;
    if (!player.preferencesReady ||
        player.output != PlaybackOutput.audioPlayer ||
        player.busy ||
        player.episode?.audioUri == null) {
      return false;
    }
    if (event is KeyDownEvent) {
      unawaited(player.toggle());
      return true;
    }
    // Holding Space must not toggle repeatedly or scroll the page.
    return event is KeyRepeatEvent;
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }
}
