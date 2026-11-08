import 'package:flutter/foundation.dart';

const mobileTranscriptionMessage =
    'Please use your desktop or laptop for transcription. '
    'You can read existing transcripts on this device.';

bool get isMobileTranscriptionDevice =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;
