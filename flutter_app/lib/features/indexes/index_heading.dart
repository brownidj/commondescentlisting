/// Filing form only: preserve the transcript and the entity's source spelling.
String indexHeading(String value) {
  final trimmed = value.trim();
  final match = RegExp(r'^(The|the)\s+(.+)$', dotAll: true).firstMatch(trimmed);
  return match == null
      ? trimmed
      : '${match.group(2)!.trim()}, ${match.group(1)}';
}

String indexBlacklistKey(String value) =>
    indexHeading(value)
        .toLowerCase()
        .replaceAll(RegExp('[–—‑]'), '-')
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
