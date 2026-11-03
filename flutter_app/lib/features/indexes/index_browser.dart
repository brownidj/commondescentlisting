import 'package:flutter/material.dart';

import '../../data/local_prepared_episodes.dart';
import '../../models/catalogue.dart';
import '../../services/episode_link.dart';
import '../../services/playback_preferences.dart';
import '../../widgets/playback_scope.dart';
import '../episodes/transcript_page.dart';
import '../episodes/segment_card.dart';
import 'index_controller.dart';
import 'index_engine.dart';
import 'index_entity_dialog.dart';
import 'index_models.dart';
import 'index_transfer.dart';
import 'index_details_panel.dart';
import 'index_reference_ranges.dart';
import 'index_accordion_item.dart';

class IndexBrowser extends StatefulWidget {
  const IndexBrowser({
    required this.catalogue,
    this.active = true,
    this.controller,
    super.key,
  });
  final Catalogue catalogue;
  final bool active;
  final KnowledgeIndexController? controller;
  @override
  State<IndexBrowser> createState() => _IndexBrowserState();
}

class _IndexBrowserState extends State<IndexBrowser>
    with WidgetsBindingObserver {
  late KnowledgeIndexController _controller;
  final _search = TextEditingController();
  IndexKind? _kind = IndexKind.fossil;
  IndexReview? _review;
  bool _descending = false;
  String _transcriptOrder = "latest";
  String? _episodeGuid;
  String? _expandedItemId;

  void _setItemExpanded(String id, bool expanded) {
    final next = expanded
        ? id
        : _expandedItemId == id
        ? null
        : _expandedItemId;
    if (next != _expandedItemId) {
      setState(() => _expandedItemId = next);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocalPreparedEpisodes.changes.addListener(_libraryChanged);
    _controller =
        widget.controller ??
        KnowledgeIndexController(catalogue: widget.catalogue);
    if (widget.active) {
      _controller.refresh();
    }
  }

  @override
  void didUpdateWidget(covariant IndexBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogue != widget.catalogue ||
        oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null) {
        _controller.dispose();
      }
      _controller =
          widget.controller ??
          KnowledgeIndexController(catalogue: widget.catalogue);
      if (widget.active) {
        _controller.refresh();
      }
    } else if (!oldWidget.active && widget.active) {
      _controller.refresh();
    }
  }

  void _libraryChanged() {
    if (widget.active) {
      _controller.refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      _controller.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocalPreparedEpisodes.changes.removeListener(_libraryChanged);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _search.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _edit([IndexEntity? entity]) async {
    final revision = _controller.registryRevision;
    final next = await showDialog<IndexEntity>(
      context: context,
      builder: (_) => IndexEntityDialog(
        kind: _kind ?? IndexKind.fossil,
        entities: _controller.entities,
        entity: entity,
      ),
    );
    if (next == null || !mounted) {
      return;
    }
    try {
      await _controller.saveEntity(next, expectedRevision: revision);
      if (mounted && entity != null && next.kind != entity.kind) {
        setState(() {
          _kind = next.kind;
          _expandedItemId = null;
          _search.clear();
          _review = next.review == IndexReview.rejected
              ? IndexReview.rejected
              : null;
        });
        _message('Entry moved to ${next.kind.label}.');
      }
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _import() async {
    try {
      final source = await importIndexRegistry();
      if (source == null || !mounted) {
        return;
      }
      IndexEntity.decode(source);
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace index registry?'),
          content: const Text(
            'This replaces names, references and review decisions on this device. Export a backup first. Transcripts are unchanged.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace == true && mounted) {
        await _controller.replaceRegistry(source);
      }
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _export() async {
    try {
      _message(await exportIndexRegistry(_controller.exportDocument));
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _openOccurrence(
    IndexOccurrence occurrence, {
    bool play = false,
  }) async {
    try {
      final current = await _controller.resolve(occurrence);
      if (!mounted) {
        return;
      }
      if (play) {
        final player = PlaybackScope.maybeOf(context);
        if (player == null ||
            player.output != PlaybackOutput.audioPlayer ||
            !player.preferencesReady ||
            !indexedAudioMatches(current.document)) {
          throw StateError(
            'Use the Audio player setting with this transcript’s matching recording.',
          );
        }
        await player.playEpisode(
          current.document.episode,
          from: current.document.audioStart(current.cue),
        );
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => TranscriptPage(
              episode: current.document.episode,
              initialPassageId: current.cue.id,
            ),
          ),
        );
        if (mounted) {
          await _controller.refresh();
        }
      }
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _openTranscript(CurrentTranscript document) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TranscriptPage(episode: document.episode),
      ),
    );
    if (mounted) {
      await _controller.refresh();
    }
  }

  Widget _quote(String text, String term) {
    if (term.trim().isEmpty) {
      return PageStorage(
        bucket: PageStorageBucket(),
        child: SelectableText(text),
      );
    }
    final spans = <TextSpan>[];
    var end = 0;
    for (final match in RegExp(
      RegExp.escape(term.trim()),
      caseSensitive: false,
    ).allMatches(text)) {
      spans.add(TextSpan(text: text.substring(end, match.start)));
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      end = match.end;
    }
    spans.add(TextSpan(text: text.substring(end)));
    return PageStorage(
      bucket: PageStorageBucket(),
      child: SelectableText.rich(TextSpan(children: spans)),
    );
  }

  Widget _occurrence(
    IndexOccurrence occurrence, {
    String? highlight,
    String? quote,
    String? referenceLabel,
  }) {
    final document = occurrence.document;
    final player = PlaybackScope.maybeOf(context);
    final playable =
        player != null &&
        player.preferencesReady &&
        !player.busy &&
        player.output == PlaybackOutput.audioPlayer &&
        indexedAudioMatches(document);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${document.episode.number == null ? "Side episode" : "Episode ${document.episode.number}"} — ${document.episode.title}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _quote(
              quote ?? occurrence.cue.text,
              highlight ?? (_kind == null ? _search.text : ''),
            ),
            Text(
              '${referenceLabel ?? "Passage ${occurrence.cue.id}"} · ${displayTime(document.audioStart(occurrence.cue))}',
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _openOccurrence(occurrence),
                  child: const Text('Open passage'),
                ),
                TextButton.icon(
                  onPressed: playable
                      ? () => _openOccurrence(occurrence, play: true)
                      : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _name(String id) =>
      _controller.entities.where((e) => e.id == id).firstOrNull?.name ?? id;

  Widget _reference(IndexEntity entity, IndexReferenceRange range) =>
      _occurrence(
        range.first,
        referenceLabel: range.label,
        highlight: entity.name,
        quote: entity.details == null
            ? null
            : entity.anchors
                  .where(
                    (a) =>
                        a.guid == range.first.document.episode.guid &&
                        a.edition == range.first.document.edition &&
                        a.passageId == range.first.cue.id,
                  )
                  .firstOrNull
                  ?.quote,
      );
  List<IndexOccurrence> _scopedMatches(String id, String? episodeGuid) =>
      (_controller.occurrences[id] ?? <IndexOccurrence>[])
          .where(
            (m) =>
                episodeGuid == null || m.document.episode.guid == episodeGuid,
          )
          .toList();

  bool _belongsToEpisode(IndexEntity entity, String? episodeGuid) =>
      episodeGuid == null ||
      entity.anchors.any((a) => a.guid == episodeGuid) ||
      _scopedMatches(entity.id, episodeGuid).isNotEmpty;

  Future<void> _showEntity(IndexEntity entity) async {
    if (_expandedItemId != null) {
      setState(() => _expandedItemId = null);
    }
    final episodeGuid = _episodeGuid;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(entity.name)),
          body: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final current = _controller.entities
                  .where((e) => e.id == entity.id)
                  .firstOrNull;
              if (current == null) {
                return const Center(child: Text('Entry no longer available.'));
              }
              final matches = _scopedMatches(current.id, episodeGuid);
              final references = groupIndexReferences(matches);
              final publications = _controller.entities.where(
                (e) =>
                    e.authorIds.contains(current.id) &&
                    _belongsToEpisode(e, episodeGuid) &&
                    e.review != IndexReview.rejected,
              );
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${current.kind.label} · ${current.review.name}',
                          ),
                          if (current.details != null)
                            IndexDetailsPanel(entity: current),
                          if (current.aliases.isNotEmpty)
                            Text(
                              'Also indexed as: ${current.aliases.join(", ")}',
                            ),
                          if (current.subtype.isNotEmpty) Text(current.subtype),
                          if (current.year != null) Text('${current.year}'),
                          if (current.publication.isNotEmpty)
                            Text(current.publication),
                          if (current.doi.isNotEmpty)
                            SelectableText('DOI: ${current.doi}'),
                          if (current.url.isNotEmpty)
                            SelectableText(current.url),
                          if ((current.doi.isNotEmpty ||
                                  current.url.isNotEmpty) &&
                              !current.linkVerified)
                            const Text(
                              'Reference link unverified; review before treating it as the cited publication.',
                            ),
                          if (current.verifiedUri != null)
                            TextButton(
                              onPressed: () async {
                                if (!await openEpisodeLink(
                                  current.verifiedUri!,
                                )) {
                                  _message(
                                    'Publication link could not be opened.',
                                  );
                                }
                              },
                              child: const Text('Open verified publication'),
                            ),
                          if (current.authorIds.isNotEmpty)
                            const Text('Authors in publication order:'),
                          for (final id in current.authorIds)
                            TextButton(
                              onPressed: () {
                                final author = _controller.entities
                                    .where((e) => e.id == id)
                                    .firstOrNull;
                                if (author != null) {
                                  _showEntity(author);
                                }
                              },
                              child: Text(_name(id)),
                            ),
                          if (current.kind == IndexKind.author) ...[
                            const Text('Indexed papers and articles:'),
                            for (final publication in publications)
                              TextButton(
                                onPressed: () => _showEntity(publication),
                                child: Text(publication.name),
                              ),
                          ],
                          if (current.note.isNotEmpty) Text(current.note),
                          Text(
                            '${references.length} references in ${matches.map((m) => m.document.episode.guid).toSet().length} episodes',
                          ),
                          if (matches.isEmpty)
                            const Text(
                              'No matches in the current transcript editions. Check aliases, quoted reference or review status.',
                            ),
                          OutlinedButton.icon(
                            onPressed: _controller.busy
                                ? null
                                : () => _edit(current),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Review / edit entry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: references.length,
                    itemBuilder: (_, i) => _reference(current, references[i]),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final query = normalizedIndexText(_search.text);
      final allDocuments = _controller.documents;
      final selectedEpisode =
          allDocuments.any((d) => d.episode.guid == _episodeGuid)
          ? _episodeGuid
          : null;
      final entities =
          _controller.entities
              .where(
                (e) =>
                    e.kind == _kind &&
                    _belongsToEpisode(e, selectedEpisode) &&
                    (_review == null
                        ? e.review != IndexReview.rejected
                        : e.review == _review) &&
                    (query.isEmpty ||
                        normalizedIndexText(
                          [
                            e.name,
                            ...e.aliases,
                            e.subtype,
                            e.publication,
                            e.doi,
                            e.details?.searchable ?? '',
                            ...e.anchors.map((a) => a.quote),
                            ...e.authorIds.map(_name),
                          ].join(' '),
                        ).contains(query)),
              )
              .toList()
            ..sort(
              (a, b) =>
                  (_descending ? -1 : 1) *
                  a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      final documents =
          allDocuments
              .where(
                (d) =>
                    selectedEpisode == null ||
                    d.episode.guid == selectedEpisode,
              )
              .toList()
            ..sort((a, b) {
              if (_transcriptOrder == 'az' || _transcriptOrder == 'za') {
                return (_transcriptOrder == 'za' ? -1 : 1) *
                    a.episode.title.toLowerCase().compareTo(
                      b.episode.title.toLowerCase(),
                    );
              }
              final first = a.episode.publishedAt;
              final second = b.episode.publishedAt;
              if (first == null || second == null) {
                return first == second
                    ? a.episode.guid.compareTo(b.episode.guid)
                    : first == null
                    ? 1
                    : -1;
              }
              final comparison =
                  first.compareTo(second) *
                  (_transcriptOrder == 'latest' ? -1 : 1);
              return comparison != 0
                  ? comparison
                  : a.episode.guid.compareTo(b.episode.guid);
            });
      final passages = <IndexOccurrence>[
        if (_kind == null && query.isNotEmpty)
          for (final d in documents)
            for (final cue in d.transcript.cues)
              if (normalizedIndexText(cue.text).contains(query))
                (document: d, cue: cue),
      ];
      return CustomScrollView(
        key: const PageStorageKey('knowledge-index-list'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 24,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Indexes',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${_controller.documents.length} available transcripts · '
                        '${_controller.entities.where((e) => e.details != null).expand((e) => _controller.occurrences[e.id] ?? <IndexOccurrence>[]).map((o) => o.document.episode.guid).toSet().length} with contextual index matches',
                      ),
                    ],
                  ),
                  const Text(
                    'Expand an entry for its description, sources and quoted passages. Suggested names, classifications and publication matches need review.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _kind?.name ?? 'transcripts',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Index',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'transcripts',
                        child: Text('Transcripts'),
                      ),
                      for (final kind in IndexKind.values)
                        DropdownMenuItem(
                          value: kind.name,
                          child: Text(kind.label),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _kind = IndexKind.values
                          .where((k) => k.name == value)
                          .firstOrNull;
                      _search.clear();
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _kind == null
                          ? 'Search all transcript passages'
                          : 'Search names, aliases, authors or references',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Clear index search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('transcript-episode-$selectedEpisode'),
                    initialValue: selectedEpisode ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Index scope',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('All entries'),
                      ),
                      for (final d in allDocuments)
                        DropdownMenuItem(
                          value: d.episode.guid,
                          child: Text(
                            '${d.episode.number ?? "Side"} — ${d.episode.title}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _episodeGuid = value == '' ? null : value;
                      _expandedItemId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (_kind == null) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _transcriptOrder,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sort transcripts',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'latest',
                          child: Text('Latest to earliest'),
                        ),
                        DropdownMenuItem(
                          value: 'earliest',
                          child: Text('Earliest to latest'),
                        ),
                        DropdownMenuItem(value: 'az', child: Text('Title A–Z')),
                        DropdownMenuItem(value: 'za', child: Text('Title Z–A')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _transcriptOrder = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_kind != null)
                        OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => _descending = !_descending),
                          icon: const Icon(Icons.sort_by_alpha),
                          label: Text(_descending ? 'Z–A' : 'A–Z'),
                        ),
                      if (_kind != null)
                        DropdownButton<IndexReview?>(
                          value: _review,
                          items: [
                            const DropdownMenuItem<IndexReview?>(
                              value: null,
                              child: Text('All except rejected'),
                            ),
                            for (final review in IndexReview.values)
                              DropdownMenuItem<IndexReview?>(
                                value: review,
                                child: Text(review.name),
                              ),
                          ],
                          onChanged: (value) => setState(() => _review = value),
                        ),
                      IconButton(
                        tooltip: 'Refresh indexes',
                        onPressed: _controller.busy
                            ? null
                            : _controller.refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: 'Add index entry',
                        onPressed: _controller.ready && !_controller.busy
                            ? _edit
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        tooltip: 'Export indexes',
                        onPressed: _controller.ready && !_controller.busy
                            ? _export
                            : null,
                        icon: const Icon(Icons.file_download_outlined),
                      ),
                      IconButton(
                        tooltip: 'Import indexes',
                        onPressed: _controller.ready && !_controller.busy
                            ? _import
                            : null,
                        icon: const Icon(Icons.file_upload_outlined),
                      ),
                    ],
                  ),
                  if (_controller.busy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Indexing transcripts',
                    ),
                  if (_controller.error != null)
                    SelectableText(_controller.error!),
                  if (_controller.loadFailures.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        '${_controller.loadFailures.length} transcripts could not be indexed',
                      ),
                      children: [
                        for (final error in _controller.loadFailures)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SelectableText(error),
                          ),
                      ],
                    ),
                  if (_kind == null && query.isNotEmpty)
                    Text('${passages.length} matching passages'),
                  if (!_controller.busy &&
                      _controller.ready &&
                      (_kind == null ? documents.isEmpty : entities.isEmpty))
                    const Text(
                      'No matching entries. Prepare a transcript, refresh, or add an index entry.',
                    ),
                ],
              ),
            ),
          ),
          if (_kind != null)
            SliverList.builder(
              itemCount: entities.length,
              itemBuilder: (_, i) {
                final entity = entities[i];
                final matches = _scopedMatches(entity.id, selectedEpisode);
                final references = groupIndexReferences(matches);
                if (entity.details != null) {
                  return Card(
                    child: IndexAccordionItem(
                      key: ValueKey('contextual-index-${entity.id}'),
                      expanded: _expandedItemId == entity.id,
                      onExpansionChanged: (expanded) =>
                          _setItemExpanded(entity.id, expanded),
                      title: Text(entity.name),
                      subtitle: Text(
                        '${entity.kind.label} / ${entity.subtype} · '
                        '${entity.review.name} · ${references.length} references',
                      ),
                      children: [
                        IndexDetailsPanel(entity: entity),
                        if (matches.isEmpty)
                          const Text(
                            'No unchanged evidence in the available transcript edition. '
                            'Prepare or load its matching edition, or reindex the corrected transcript.',
                          ),
                        for (final reference in references)
                          _reference(entity, reference),
                        OutlinedButton.icon(
                          onPressed: () => _showEntity(entity),
                          icon: const Icon(Icons.manage_search),
                          label: const Text('Review entry / author links'),
                        ),
                      ],
                    ),
                  );
                }
                return ListTile(
                  title: Text(entity.name),
                  subtitle: Text(
                    '${entity.review.name} · ${references.length} references · '
                    '${matches.map((m) => m.document.episode.guid).toSet().length} episodes',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showEntity(entity),
                );
              },
            )
          else if (query.isNotEmpty)
            SliverList.builder(
              itemCount: passages.length,
              itemBuilder: (_, i) => _occurrence(passages[i]),
            )
          else
            SliverList.builder(
              itemCount: documents.length,
              itemBuilder: (_, i) {
                final d = documents[i];
                return ListTile(
                  title: Text(d.episode.title),
                  subtitle: Text(
                    '${d.episode.number == null ? "Side episode" : "Episode ${d.episode.number}"} · ${d.transcript.cues.length} passages · ${d.transcript.label}'
                    '${d.episode.publishedAt == null ? "" : " · ${d.episode.publishedAt!.toIso8601String().substring(0, 10)}"}',
                  ),
                  trailing: const Icon(Icons.article_outlined),
                  onTap: () => _openTranscript(d),
                );
              },
            ),
        ],
      );
    },
  );
}
