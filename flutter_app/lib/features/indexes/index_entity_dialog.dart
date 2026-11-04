import 'package:flutter/material.dart';

import 'index_models.dart';
import 'index_author_links.dart';

class IndexEntityDialog extends StatefulWidget {
  const IndexEntityDialog({
    required this.kind,
    required this.entities,
    this.entity,
    super.key,
  });
  final IndexKind kind;
  final List<IndexEntity> entities;
  final IndexEntity? entity;
  @override
  State<IndexEntityDialog> createState() => _IndexEntityDialogState();
}

class _IndexEntityDialogState extends State<IndexEntityDialog> {
  final _form = GlobalKey<FormState>();
  late IndexKind _kind;
  late IndexReview _review;
  late bool _verified;
  late final List<String> _authors;
  final _fields = <String, TextEditingController>{};
  String? _error;
  bool get _publication =>
      _kind == IndexKind.paper || _kind == IndexKind.article;
  @override
  void initState() {
    super.initState();
    final e = widget.entity;
    _kind = e?.kind ?? widget.kind;
    _review = e?.review ?? IndexReview.suggested;
    _verified = e?.linkVerified ?? false;
    _authors = [...?e?.authorIds];
    for (final item in {
      'Name / title': e?.name ?? '',
      'Aliases (one per line)': e?.aliases.join('\n') ?? '',
      'Classification': e?.subtype ?? '',
      'Year': e?.year?.toString() ?? '',
      'Journal / publisher': e?.publication ?? '',
      'DOI': e?.doi ?? '',
      'Web URL': e?.url ?? '',
      'Review notes': e?.note ?? '',
    }.entries) {
      _fields[item.key] = TextEditingController(text: item.value);
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, {int lines = 1}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: _fields[label],
      minLines: lines,
      maxLines: lines,
      maxLength: label == 'Review notes' ? 20000 : 1000,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        counterText: '',
        hintText: label == 'Classification'
            ? 'e.g. extant species, genus, country or person'
            : null,
      ),
      validator: (value) =>
          label == 'Name / title' && (value?.trim().isEmpty ?? true)
          ? 'Enter a name or title.'
          : null,
    ),
  );
  void _save() {
    if (!_form.currentState!.validate()) {
      return;
    }
    String text(String key) => _fields[key]!.text.trim();
    final year = text('Year');
    if (_publication && year.isNotEmpty && int.tryParse(year) == null) {
      setState(() => _error = 'Year must be a number.');
      return;
    }
    final entity = IndexEntity(
      id:
          widget.entity?.id ??
          'manual:${DateTime.now().microsecondsSinceEpoch}',
      kind: _kind,
      name: text('Name / title'),
      review: _review,
      aliases: text('Aliases (one per line)')
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet(),
      subtype: text('Classification'),
      year: _publication ? int.tryParse(year) : null,
      publication: _publication ? text('Journal / publisher') : '',
      doi: _publication ? text('DOI') : '',
      url: _publication ? text('Web URL') : '',
      linkVerified: _publication && _verified,
      authorIds: _publication ? _authors : [],
      anchors: widget.entity?.anchors ?? const [],
      note: text('Review notes'),
      details: widget.entity?.details,
      variantIds: widget.entity?.variantIds ?? const [],
    );
    try {
      // Validate the whole registry, including ordered shared-author references.
      reconcileIndexAuthorLinks([
        ...widget.entities.where((e) => e.id != entity.id),
        entity,
      ]);
      Navigator.pop(context, entity);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authors =
        widget.entities.where((e) => e.kind == IndexKind.author).toList()..sort(
          (a, b) => a.heading.toLowerCase().compareTo(b.heading.toLowerCase()),
        );
    return AlertDialog(
      scrollable: true,
      title: Text(
        widget.entity == null ? 'Add index entry' : 'Review index entry',
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<IndexKind>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Index'),
                items: [
                  for (final kind in IndexKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (kind) {
                  if (kind != null && kind != _kind) {
                    setState(() {
                      _kind = kind;
                      _fields['Classification']!.clear();
                      _error = null;
                    });
                  }
                },
              ),
              _field('Name / title'),
              _field('Aliases (one per line)', lines: 3),
              DropdownButtonFormField<IndexReview>(
                initialValue: _review,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Review status'),
                items: [
                  for (final review in IndexReview.values)
                    DropdownMenuItem(value: review, child: Text(review.name)),
                ],
                onChanged: (review) {
                  if (review != null) {
                    setState(() => _review = review);
                  }
                },
              ),
              _field('Classification'),
              if (_kind == IndexKind.fossil)
                const Text(
                  'Taxonomy includes living and extinct organisms at all ranks: phylum, class, order, family, genus and species.',
                ),
              if (widget.entity?.kind == IndexKind.author &&
                  _kind != IndexKind.author &&
                  widget.entities.any(
                    (e) => e.authorIds.contains(widget.entity!.id),
                  ))
                const Text(
                  'Saving will remove this entry from publication author lists and flag those attributions for review.',
                ),
              if (_publication) ...[
                _field('Year'),
                _field('Journal / publisher'),
                _field('DOI'),
                _field('Web URL'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _verified,
                  title: const Text(
                    'I checked this DOI / web link against the publication',
                  ),
                  onChanged: (value) =>
                      setState(() => _verified = value ?? false),
                ),
                const Text(
                  'Authors in publication order. Add missing authors in Authors first.',
                ),
                for (var i = 0; i < _authors.length; i++)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          authors
                                  .where((a) => a.id == _authors[i])
                                  .firstOrNull
                                  ?.heading ??
                              _authors[i],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Move author up',
                        icon: const Icon(Icons.arrow_upward),
                        onPressed: i == 0
                            ? null
                            : () => setState(() {
                                final id = _authors.removeAt(i);
                                _authors.insert(i - 1, id);
                              }),
                      ),
                      IconButton(
                        tooltip: 'Move author down',
                        icon: const Icon(Icons.arrow_downward),
                        onPressed: i == _authors.length - 1
                            ? null
                            : () => setState(() {
                                final id = _authors.removeAt(i);
                                _authors.insert(i + 1, id);
                              }),
                      ),
                      IconButton(
                        tooltip: 'Remove author',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _authors.removeAt(i)),
                      ),
                    ],
                  ),
                DropdownButtonFormField<String>(
                  key: ValueKey(_authors.join('|')),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Add author'),
                  items: [
                    for (final a in authors.where(
                      (a) => !_authors.contains(a.id),
                    ))
                      DropdownMenuItem(value: a.id, child: Text(a.heading)),
                  ],
                  onChanged: (id) {
                    if (id != null) {
                      setState(() => _authors.add(id));
                    }
                  },
                ),
              ],
              _field('Review notes', lines: 3),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
