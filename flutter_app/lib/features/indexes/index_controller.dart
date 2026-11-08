import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/bundled_transcripts.dart';
import '../../data/local_prepared_episodes.dart';
import '../../models/catalogue.dart';
import '../../services/current_transcript.dart';
import 'index_engine.dart';
import 'index_models.dart';
import 'index_author_links.dart';
import 'index_store.dart';
import 'index_word_forms.dart';
import 'index_deletion_blacklist.dart';
import 'index_addition_policy.dart';

Future<CurrentTranscript> loadIndexedTranscript(Episode episode) =>
    loadCurrentTranscript(episode);
bool indexedAudioMatches(CurrentTranscript document) =>
    currentTranscriptAudioMatches(document);

Future<List<IndexEntity>> loadLocalIndexEntries() async {
  final result = IndexEntity.decode(
    await rootBundle.loadString('assets/data/local_indexes.json'),
  );
  final blacklist = jsonDecode(
    await rootBundle.loadString('assets/data/index_deletion_blacklist.json'),
  ) as Map<String, dynamic>;
  if (blacklist['schema_version'] != 1 || blacklist['entries'] is! List) {
    throw const FormatException('Invalid project deletion blacklist.');
  }
  var deletion = 0;
  for (final row in blacklist['entries'] as List) {
    final raw = Map<String, dynamic>.from(row as Map);
    if (raw['deleted'] != true) {
      continue;
    }
    final originalId = raw['id'] as String;
    result.addAll(
      IndexEntity.decode(
        jsonEncode({
          'schema_version': 1,
          'entries': [
            {
              ...raw,
              'id': 'blacklist:${deletion++}:$originalId',
              'variant_ids': [
                originalId,
                ...(raw['variant_ids'] as List? ?? const []),
              ],
            },
          ],
        }),
      ),
    );
  }
  for (final local in LocalPreparedEpisodes.editions.where((e) => e.hasIndex)) {
    final entries = IndexEntity.decode(
      await local.loadText('indexing/index.json'),
    );
    if (entries.any(
      (e) => e.anchors.any(
        (a) => a.guid != local.guid || a.edition != local.edition,
      ),
    )) {
      throw const FormatException('Local index edition mismatch.');
    }
    result.addAll(entries);
  }
  return result;
}

class KnowledgeIndexController extends ChangeNotifier {
  KnowledgeIndexController({
    required this.catalogue,
    IndexRegistryStore? store,
    Future<CurrentTranscript> Function(Episode)? loadTranscript,
    bool Function(String)? available,
    Future<String> Function()? vocabulary,
    Future<String> Function()? contextualIndex,
    bool? enableHeuristicSuggestions,
    Future<List<IndexEntity>> Function()? localIndexes,
  }) : store = store ?? FileIndexRegistryStore(),
       _loadTranscript = loadTranscript ?? loadIndexedTranscript,
       _available = available ?? BundledTranscripts.hasEpisode,
       _vocabulary =
           vocabulary ??
           (() => rootBundle.loadString('assets/data/index_vocabulary.json')),
       _contextualIndex =
           contextualIndex ??
           (vocabulary != null
               ? (() async => IndexEntity.encode([]))
               : (() => rootBundle.loadString(
                   'assets/data/contextual_indexes.json',
                 ))),
       _localIndexes =
           localIndexes ??
           (vocabulary != null || contextualIndex != null
               ? (() async => <IndexEntity>[])
               : loadLocalIndexEntries),
       _legacySuggestions = enableHeuristicSuggestions ?? vocabulary != null;
  final Catalogue catalogue;
  final IndexRegistryStore store;
  final Future<CurrentTranscript> Function(Episode) _loadTranscript;
  final bool Function(String) _available;
  final Future<String> Function() _vocabulary;
  final Future<String> Function() _contextualIndex;
  final bool _legacySuggestions;
  final Future<List<IndexEntity>> Function() _localIndexes;
  Set<String> _legacyIds = {};
  List<IndexEntity> _registry = [];
  List<IndexEntity> entities = [];
  List<CurrentTranscript> documents = [];
  Map<String, List<IndexOccurrence>> occurrences = {};
  List<String> loadFailures = [];
  bool busy = false;
  bool ready = false;
  bool _disposed = false;
  bool _refreshPending = false;
  String? error;
  String? _saved;
  PassageIndex? _passageIndex;
  String? get registryRevision => _saved;
  void _changed() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    if (busy) {
      _refreshPending = true;
      return;
    }
    busy = true;
    error = null;
    _changed();
    try {
      final saved = await store.read();
      final vocabulary = IndexEntity.decode(await _vocabulary());
      final contextual = IndexEntity.decode(await _contextualIndex());
      contextual.addAll(await _localIndexes());
      _legacyIds = vocabulary.map((e) => e.id).toSet();
      final registry = saved == null
          ? <IndexEntity>[]
          : IndexEntity.decode(saved);
      final loaded = <CurrentTranscript>[];
      final failures = <String>[];
      for (final episode in catalogue.episodes.where(
        (e) => _available(e.guid),
      )) {
        try {
          loaded.add(await _loadTranscript(episode));
        } catch (exception) {
          failures.add('${episode.title}: $exception');
        }
      }
      if (_disposed) {
        return;
      }
      final passageIndex = PassageIndex(loaded);
      final deletedIds = {
        for (final e in [
          ...registry,
          ...contextual,
        ].where((e) => e.deleted)) ...[e.id, ...e.variantIds],
      };
      final blacklist = IndexDeletionBlacklist([...registry, ...contextual]);
      final merged = {
        for (final e in contextual.where((e) => e.deleted)) e.id: e,
        for (final e in registry) e.id: e,
      };
      for (final e in _legacySuggestions ? vocabulary : <IndexEntity>[]) {
        if (!deletedIds.contains(e.id) &&
            !blacklist.blocks(e) &&
            !merged.containsKey(e.id) &&
            passageIndex.find(e).isNotEmpty) {
          merged[e.id] = e;
        }
      }
      for (final e
          in _legacySuggestions
              ? suggestIndexEntries(loaded)
              : <IndexEntity>[]) {
        if (!deletedIds.contains(e.id) && !blacklist.blocks(e)) {
          merged.putIfAbsent(e.id, () => e);
        }
      }
      // Bundle and server may both carry the same entity, scoped to different
      // episodes. Combine evidence before applying saved review decisions.
      final sources = <String, Map<String, dynamic>>{};
      for (final entity in contextual) {
        final row = sources.putIfAbsent(entity.id, entity.toJson);
        final anchors = <String, Map<String, dynamic>>{
          for (final anchor
              in (row['anchors'] as List).cast<Map<String, dynamic>>())
            jsonEncode(anchor): anchor,
          for (final anchor in entity.anchors)
            jsonEncode(anchor.toJson()): anchor.toJson(),
        };
        row['anchors'] = anchors.values.toList();
      }
      final combined = IndexEntity.decode(
        jsonEncode({'schema_version': 1, 'entries': sources.values.toList()}),
      );
      for (final e in combined) {
        if (deletedIds.contains(e.id) || blacklist.blocks(e)) {
          continue;
        }
        final existing = merged[e.id];
        merged[e.id] = existing == null ? e : _updatedEvidence(existing, e);
      }
      // Validate references before committing any derived suggestions.
      final next = IndexEntity.decode(
        IndexEntity.encode(
          mergeIndexWordForms(
            reconcileIndexAuthorLinks(blacklist.apply(merged.values)),
          ),
        ),
      );
      final encoded = IndexEntity.encode(next);
      if (encoded != saved && !await store.save(encoded, expected: saved)) {
        throw StateError(
          'Index changed elsewhere. Refresh before saving; no data overwritten.',
        );
      }
      if (_disposed) {
        return;
      }
      _saved = encoded;
      _registry = next;
      entities = _visible(next);
      documents = loaded;
      loadFailures = failures;
      _passageIndex = passageIndex;
      _rebuild();
      ready = true;
    } catch (exception) {
      if (!_disposed) {
        error = '$exception';
      }
    } finally {
      busy = false;
      _changed();
      if (_refreshPending && !_disposed) {
        _refreshPending = false;
        await refresh();
      }
    }
  }

  List<IndexEntity> _visible(List<IndexEntity> entries) => entries.where((e) {
    if (e.deleted) {
      return false;
    }
    if (_legacySuggestions ||
        e.details != null ||
        e.review != IndexReview.suggested ||
        e.id.startsWith('manual:')) {
      return true;
    }
    // Hide the old automatic guesses, retaining their saved records and every
    // explicit review decision. Refresh no longer generates heuristic entries.
    return !_legacyIds.contains(e.id) &&
        ![
          'Possible place or geological unit in transcript wording.',
          'Literal author wording in transcript;',
          'Possible scientific name near taxonomic wording.',
          'Reference mentioned in transcript. Title, author attribution',
        ].any(e.note.startsWith);
  }).toList();

  IndexEntity _updatedEvidence(IndexEntity saved, IndexEntity bundled) {
    if (saved.deleted) {
      return saved;
    }
    final snapshot = bundled.details?.refinementSource ?? '';
    if (saved.review == IndexReview.suggested && snapshot.isNotEmpty) {
      final decoded = jsonDecode(snapshot);
      final snapshots = decoded is List ? decoded : [decoded];
      final current = saved.toJson();
      const metadata = {
        'name',
        'kind',
        'review',
        'aliases',
        'subtype',
        'year',
        'publication',
        'doi',
        'url',
        'link_verified',
        'author_ids',
        'note',
      };
      if (snapshots.any(
        (before) =>
            before is Map<String, dynamic> &&
            before.keys.toSet().containsAll(metadata) &&
            before.length == metadata.length &&
            before.entries.every(
              (e) => jsonEncode(current[e.key]) == jsonEncode(e.value),
            ),
      )) {
        // Only untouched suggestions adopt refinement/enrichment changes.
        // Explicitly reviewed or edited metadata stays with the listener.
        return bundled.copyWith(
          variantIds: {...saved.variantIds, ...bundled.variantIds},
        );
      }
    }
    return IndexEntity(
      id: saved.id,
      kind: saved.kind,
      name: saved.name,
      review: saved.review,
      aliases: saved.aliases,
      subtype: saved.subtype,
      year: saved.year,
      publication: saved.publication,
      doi: saved.doi,
      url: saved.url,
      linkVerified: saved.linkVerified,
      authorIds: saved.authorIds,
      note: saved.note,
      details: bundled.details,
      anchors: bundled.anchors,
      variantIds: {...saved.variantIds, ...bundled.variantIds}.toList(),
    );
  }

  String get exportDocument => IndexEntity.encode(_registry);

  String? additionProblem(IndexEntity entity) =>
      indexAdditionProblem(entity, _registry);

  void _rebuild() {
    final index = _passageIndex ??= PassageIndex(documents);
    occurrences = {for (final e in entities) e.id: index.find(e)};
  }

  Future<void> saveEntity(
    IndexEntity entity, {
    String? expectedRevision,
  }) async {
    if (!_registry.any((entry) => entry.id == entity.id && !entry.deleted)) {
      final problem = additionProblem(entity);
      if (problem != null) {
        throw StateError(problem);
      }
    }
    if (expectedRevision != null && expectedRevision != _saved) {
      throw StateError(
        'Index changed while this entry was open. Reopen it before saving.',
      );
    }
    final next = [..._registry.where((e) => e.id != entity.id), entity];
    await replaceRegistry(IndexEntity.encode(reconcileIndexAuthorLinks(next)));
  }

  Future<void> deleteEntity(
    String id, {
    required String expectedRevision,
  }) async {
    await deleteEntities({id}, expectedRevision: expectedRevision);
  }

  Future<void> deleteEntities(
    Set<String> selectedIds, {
    required String expectedRevision,
  }) async {
    if (_saved != expectedRevision) {
      throw StateError(
        'Index changed while confirming deletion. Refresh and try again.',
      );
    }
    if (selectedIds.isEmpty) {
      return;
    }
    final entries = _registry
        .where((e) => selectedIds.contains(e.id) && !e.deleted)
        .toList();
    if (entries.length != selectedIds.length) {
      throw StateError('Entries no longer available. Refresh indexes.');
    }
    final ids = {
      for (final entry in entries) ...[entry.id, ...entry.variantIds],
    };
    final rows = [
      for (final e in _registry)
        {...e.toJson(), if (ids.contains(e.id)) 'deleted': true},
    ];
    final next = IndexEntity.decode(
      jsonEncode({'schema_version': 1, 'entries': rows}),
    );
    await replaceRegistry(IndexEntity.encode(reconcileIndexAuthorLinks(next)));
  }

  Future<void> replaceRegistry(String source) async {
    if (busy || !ready) {
      throw StateError('Indexes are not ready.');
    }
    final incoming = IndexEntity.decode(source);
    // Registry import/replacement cannot erase the listener's deletion history.
    final tombstones = {
      for (final e in [...incoming, ..._registry])
        if (e.deleted) e.id: e,
    };
    final blacklist = IndexDeletionBlacklist(tombstones.values);
    final next = mergeIndexWordForms(
      reconcileIndexAuthorLinks(
        blacklist.apply([
          for (final e in incoming)
            if (!tombstones.containsKey(e.id)) e,
          ...tombstones.values,
        ]),
      ),
    );
    final encoded = IndexEntity.encode(next);
    busy = true;
    error = null;
    _changed();
    try {
      if (!await store.save(encoded, expected: _saved)) {
        throw StateError(
          'Index changed elsewhere. Refresh before saving; no data overwritten.',
        );
      }
      if (_disposed) {
        return;
      }
      _saved = encoded;
      _registry = next;
      entities = _visible(next);
      _rebuild();
    } finally {
      busy = false;
      _changed();
      if (_refreshPending && !_disposed) {
        _refreshPending = false;
        await refresh();
      }
    }
  }

  Future<IndexOccurrence> resolve(IndexOccurrence occurrence) async {
    final current = await _loadTranscript(occurrence.document.episode);
    final cue = current.transcript.cues
        .where((c) => c.id == occurrence.cue.id)
        .firstOrNull;
    if (current.edition != occurrence.document.edition ||
        current.transcript.audioIdentity !=
            occurrence.document.transcript.audioIdentity ||
        cue == null ||
        cue.text != occurrence.cue.text) {
      throw StateError(
        'Transcript changed. Refresh indexes before using this result.',
      );
    }
    return (document: current, cue: cue);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
