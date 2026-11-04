import 'dart:convert';

/// Review information is kept separate from names and literal passage evidence.
class IndexDetails {
  const IndexDetails({
    this.spoken = const [],
    this.description = '',
    this.confidence = '',
    this.normalizations = const [],
    this.editorialNote = '',
    this.bibliography = '',
    this.originalPublication = '',
    this.sources = const [],
    this.model = '',
    this.refinementSource = '',
    this.externalConfirmation = '',
  });
  final List<String> spoken;
  final String description;
  final String confidence;
  final List<String> normalizations;
  final String editorialNote;
  final String bibliography;
  final String originalPublication;
  final List<IndexSource> sources;
  final String model;

  /// Metadata before API refinement, used only to protect saved human edits.
  final String refinementSource;

  /// Source identity confirmation, separate from human review status.
  final String externalConfirmation;

  String get searchable => [
    ...spoken,
    description,
    editorialNote,
    bibliography,
    originalPublication,
  ].join(' ');

  Map<String, dynamic> toJson() => {
    'spoken': spoken,
    'description': description,
    'confidence': confidence,
    'normalizations': normalizations,
    'editorial_note': editorialNote,
    'bibliography': bibliography,
    'original_publication': originalPublication,
    'sources': sources.map((s) => s.toJson()).toList(),
    'model': model,
    if (refinementSource.isNotEmpty) 'refinement_source': refinementSource,
    if (externalConfirmation.isNotEmpty)
      'external_confirmation': externalConfirmation,
  };

  static IndexDetails? decode(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid index review details.');
    }
    String text(String key) {
      final value = raw[key] ?? '';
      if (value is! String || value.length > 100000) {
        throw FormatException('Invalid review $key.');
      }
      return value;
    }

    List<String> strings(String key) {
      final value = raw[key] ?? [];
      if (value is! List ||
          value.length > 1000 ||
          value.any((s) => s is! String || s.length > 20000)) {
        throw FormatException('Invalid review $key.');
      }
      return List.unmodifiable(value.cast<String>());
    }

    for (final key in [
      'bibliography',
      'original_publication',
      'refinement_source',
      'external_confirmation',
    ]) {
      final value = text(key);
      if (value.isNotEmpty) {
        final decoded = jsonDecode(value);
        if (decoded is! Map && decoded is! List) {
          throw const FormatException('Invalid bibliography JSON.');
        }
      }
    }
    final sources = raw['sources'] ?? [];
    if (sources is! List || sources.length > 100) {
      throw const FormatException('Invalid bibliography sources.');
    }
    return IndexDetails(
      spoken: strings('spoken'),
      description: text('description'),
      confidence: text('confidence'),
      normalizations: strings('normalizations'),
      editorialNote: text('editorial_note'),
      bibliography: text('bibliography'),
      originalPublication: text('original_publication'),
      model: text('model'),
      refinementSource: text('refinement_source'),
      externalConfirmation: text('external_confirmation'),
      sources: List.unmodifiable(sources.map(IndexSource.decode)),
    );
  }
}

class IndexSource {
  const IndexSource({required this.url, required this.label});
  final String url;
  final String label;
  Map<String, String> toJson() => {'url': url, 'label': label};
  static IndexSource decode(dynamic raw) {
    if (raw is! Map || raw['url'] is! String || raw['label'] is! String) {
      throw const FormatException('Invalid index source.');
    }
    final url = raw['url'] as String;
    final label = raw['label'] as String;
    final uri = Uri.tryParse(url);
    if (url.length > 4000 ||
        label.length > 4000 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid index source URL.');
    }
    return IndexSource(url: url, label: label);
  }
}
