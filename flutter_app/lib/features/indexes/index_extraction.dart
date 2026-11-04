/// Literal occurrence provenance. Scores never imply human confirmation.
class IndexExtraction {
  const IndexExtraction({
    required this.method,
    required this.label,
    required this.start,
    required this.end,
    required this.extractorVersion,
    this.score,
    this.model = '',
    this.modelRevision = '',
  });

  final String method;
  final String label;
  final int start;
  final int end;
  final String extractorVersion;
  final double? score;
  final String model;
  final String modelRevision;

  Map<String, dynamic> toJson() => {
    'method': method,
    'label': label,
    'score': score,
    'start': start,
    'end': end,
    'offset_unit': 'unicode_code_points',
    'extractor_version': extractorVersion,
    'model': model,
    'model_revision': modelRevision,
  };

  static List<IndexExtraction> decode(
    dynamic rows,
    String? passageText,
    String quote,
  ) {
    if (rows == null) return const [];
    if (rows is! List || rows.length > 100) {
      throw const FormatException('Invalid extraction evidence.');
    }
    final result = <IndexExtraction>[];
    for (final row in rows) {
      if (row is! Map || passageText == null) {
        throw const FormatException('Extraction requires passage text.');
      }
      String text(String key, {bool required = false}) {
        final value = row[key] ?? '';
        if (value is! String ||
            value.length > 1000 ||
            (required && value.isEmpty)) {
          throw const FormatException('Invalid extraction metadata.');
        }
        return value;
      }

      final start = row['start'];
      final end = row['end'];
      final score = row['score'];
      final points = passageText.runes.toList();
      if (row['offset_unit'] != 'unicode_code_points' ||
          start is! int ||
          end is! int ||
          start < 0 ||
          end <= start ||
          end > points.length ||
          String.fromCharCodes(points.sublist(start, end)) != quote ||
          (score != null &&
              (score is! num || !score.isFinite || score < 0 || score > 1))) {
        throw const FormatException('Invalid extraction span or score.');
      }
      result.add(
        IndexExtraction(
          method: text('method', required: true),
          label: text('label', required: true),
          start: start,
          end: end,
          extractorVersion: text('extractor_version', required: true),
          score: (score as num?)?.toDouble(),
          model: text('model'),
          modelRevision: text('model_revision'),
        ),
      );
    }
    return List.unmodifiable(result);
  }
}
