import 'package:flutter/material.dart';

import '../../data/bundled_transcripts.dart';
import '../../data/local_prepared_episodes.dart';
import '../../data/episode_audio.dart';
import '../../models/catalogue.dart';
import '../../models/episode_transcript.dart';
import '../../services/playback_preferences.dart';
import '../../services/playback_controller.dart';
import '../../services/transcript_edits.dart';
import '../../services/file_transcript_edits.dart';
import '../../services/transcript_export.dart';
import '../../services/transcript_pdf.dart';
import '../../services/transcript_timing_diagnostics.dart';
import '../../widgets/playback_scope.dart';
import '../../widgets/playback_route_observer.dart';
import 'transcript_search.dart';
import 'transcript_editor_dialog.dart';
import 'transcript_follow.dart';
import 'transcript_passage_list.dart';
import 'transcript_timing_dialog.dart';

class TranscriptPage extends StatefulWidget {
  const TranscriptPage({
    required this.episode,
    this.initialPassageId,
    this.loadTranscript = BundledTranscripts.load,
    this.editStore,
    this.exportTranscript = exportTranscriptFiles,
    this.exportPdf = createTranscriptPdf,
    super.key,
  });

  final Episode episode;
  final int? initialPassageId;
  final Future<EpisodeTranscript> Function(String guid) loadTranscript;
  final TranscriptEditStore? editStore;
  final TranscriptExporter exportTranscript;
  final TranscriptPdfExporter exportPdf;

  @override
  State<TranscriptPage> createState() => _TranscriptPageState();
}

class _TranscriptPageState extends State<TranscriptPage> with RouteAware {
  late Episode _displayEpisode;
  late Future<EpisodeTranscript> _transcript;
  bool _showOriginal = false;
  final _searchController = TextEditingController();
  int _scrollReset = 0;
  var _search = TranscriptSearch('');
  TranscriptEdits? _edits;
  bool _exporting = false;
  bool _editing = false;
  bool _diagnosing = false;
  final _timingDiagnostics = <String, TranscriptTimingDiagnostics>{};
  int? _selectedCueId;
  bool _indexFocus = false;
  PlaybackController? _editPlayer;
  int _lastSeekRevision = 0;
  ModalRoute<dynamic>? _route;
  bool _routeVisible = true;
  int _loadGeneration = 0;
  Episode? _pendingEpisodeChange;
  String? _localEdition;
  String? get _editionSourceKey {
    final edition = LocalPreparedEpisodes.forGuid(_displayEpisode.guid);
    return edition == null
        ? null
        : '${edition.edition}|${edition.readOnly}|${edition.audioUri}';
  }

  TranscriptCue? get _highlightedCue {
    final player = _editPlayer;
    final edits = _edits;
    if (player == null ||
        edits == null ||
        player.episode?.guid != _displayEpisode.guid ||
        player.output != PlaybackOutput.audioPlayer) {
      return null;
    }
    if (_selectedCueId != null) {
      for (final cue in edits.current.cues) {
        if (cue.id == _selectedCueId) return cue;
      }
    }
    final cue = transcriptCueAt(
      edits.current.cues,
      player.position + edits.syncOffset,
    );
    if (cue != null &&
        !player.playing &&
        _search.isActive &&
        _search.matches(_showOriginal ? cue.originalText : cue.text).isEmpty) {
      return null;
    }
    return cue;
  }

  bool _canEditHighlighted() =>
      mounted &&
      LocalPreparedEpisodes.forGuid(_displayEpisode.guid)?.readOnly != true &&
      !_diagnosing &&
      !_editing &&
      !_exporting &&
      _edits?.ready == true &&
      _edits?.busy == false &&
      _edits?.conflict == false &&
      _highlightedCue != null;

  TranscriptCue? get _selectedCue {
    final selectedId = _selectedCueId;
    final edits = _edits;
    if (selectedId == null || edits == null) return null;
    for (final cue in edits.current.cues) {
      if (cue.id == selectedId) return cue;
    }
    return null;
  }

  bool _canEditSelected() =>
      mounted &&
      LocalPreparedEpisodes.forGuid(_displayEpisode.guid)?.readOnly != true &&
      !_diagnosing &&
      !_editing &&
      !_exporting &&
      _editPlayer?.busy != true &&
      _edits?.ready == true &&
      _edits?.busy == false &&
      _edits?.conflict == false &&
      _selectedCue != null;

  void _openHighlighted() {
    if (!_canEditHighlighted()) return;
    final cue = _highlightedCue;
    if (cue != null) _editCue(cue);
  }

  void _openSelected() {
    if (!_canEditSelected()) return;
    final cue = _selectedCue;
    if (cue != null) _editCue(cue);
  }

  bool _canCreatePdf() {
    final edits = _edits;
    return mounted && _routeVisible && !_editing && !_exporting &&
        !_diagnosing && edits != null && edits.ready && !edits.busy &&
        !edits.conflict;
  }

  Future<void> _createPdf() async {
    if (!_canCreatePdf()) return;
    final guid = _displayEpisode.guid;
    final passages = _edits!.current.cues.map((cue) => cue.text).toList();
    setState(() => _exporting = true);
    _editPlayer?.refreshTranscriptEdit();
    try {
      final path = await widget.exportPdf(guid, passages);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF saved to $path')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create PDF. Check the preparation worker connection. $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
        _editPlayer?.refreshTranscriptEdit();
        final pendingEpisode = _pendingEpisodeChange;
        if (pendingEpisode != null) _loadEpisode(pendingEpisode);
      }
    }
  }

  Future<void> _openTimingDiagnostics() async {
    final edits = _edits;
    final player = _editPlayer;
    if (edits == null ||
        !edits.ready ||
        edits.busy ||
        player == null ||
        _editing ||
        _exporting ||
        _diagnosing) {
      return;
    }
    setState(() => _diagnosing = true);
    player.refreshTranscriptEdit();
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => TranscriptTimingDialog(
          episode: _displayEpisode,
          player: player,
          edits: edits,
          diagnostics: _timingDiagnostics.putIfAbsent(
            _displayEpisode.guid,
            () => TranscriptTimingDiagnostics(
              _displayEpisode.guid,
              audioIdentity: edits.baseline.audioIdentity,
            ),
          ),
          initialPassageId:
              _selectedCueId ??
              (player.episode?.guid == _displayEpisode.guid
                  ? player.currentPassage?.id
                  : null),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _diagnosing = false);
        player.refreshTranscriptEdit();
        final pendingEpisode = _pendingEpisodeChange;
        if (pendingEpisode != null) _loadEpisode(pendingEpisode);
      }
    }
  }

  void _bindPlayerEdit() {
    final player = _editPlayer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(player, _editPlayer) && _edits?.ready == true) {
        player?.setTranscriptContext(_edits!.current, _edits!.syncOffset);
        player?.registerTranscriptEdit(
          this,
          _displayEpisode.guid,
          _openHighlighted,
          _canEditHighlighted,
          _routeVisible,
          createPdf: _createPdf,
          canCreatePdf: _canCreatePdf,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<dynamic>(context);
    final routeChanged = !identical(route, _route);
    if (routeChanged) {
      if (_route != null) playbackRouteObserver.unsubscribe(this);
      _route = route;
      _routeVisible = route?.isCurrent ?? true;
      if (route != null) playbackRouteObserver.subscribe(this, route);
    }
    final player = PlaybackScope.maybeOf(context);
    final playerChanged = !identical(player, _editPlayer);
    if (playerChanged) {
      final previous = _editPlayer;
      _editPlayer = player;
      _lastSeekRevision = player?.seekRevision ?? 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous?.unregisterTranscriptEdit(this);
      });
    } else if (player != null && player.seekRevision != _lastSeekRevision) {
      _lastSeekRevision = player.seekRevision;
      // Explicit seeking resumes audio-follow; ordinary playback still leaves
      // a right-click edit selection stationary until cleared or edited.
      if (!_editing && !_diagnosing) _selectedCueId = null;
    }
    if (routeChanged || playerChanged) _bindPlayerEdit();
  }

  void _setRouteVisible(bool visible) {
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    _bindPlayerEdit();
    _editPlayer?.refreshTranscriptEdit();
  }

  @override
  void didPush() => _setRouteVisible(true);

  @override
  void didPopNext() => _setRouteVisible(true);

  @override
  void didPushNext() => _setRouteVisible(false);

  @override
  void didPop() => _setRouteVisible(false);

  @override
  void initState() {
    super.initState();
    _displayEpisode = widget.episode;
    _indexFocus = widget.initialPassageId != null;
    _localEdition = _editionSourceKey;
    LocalPreparedEpisodes.changes.addListener(_preparedEditionChanged);
    _transcript = _load(
      _displayEpisode,
      widget.loadTranscript,
      widget.editStore,
      ++_loadGeneration,
    );
  }

  void _preparedEditionChanged() {
    if (!mounted) return;
    final next = _editionSourceKey;
    if (next == _localEdition) return;
    _localEdition = next;
    _timingDiagnostics.remove(_displayEpisode.guid);
    // Existing edit/export/diagnostic deferral also protects edition changes.
    _loadEpisode(_displayEpisode);
  }

  @override
  void didUpdateWidget(covariant TranscriptPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.guid == widget.episode.guid) {
      if (!_editing && !_exporting && !_diagnosing) {
        _displayEpisode = widget.episode;
        if (oldWidget.initialPassageId != widget.initialPassageId) {
          _indexFocus = widget.initialPassageId != null;
          _selectedCueId = null;
          _scrollReset++;
        }
      }
      return;
    }
    if (_editing || _exporting || _diagnosing) {
      _pendingEpisodeChange = widget.episode;
      return;
    }
    _loadEpisode(widget.episode);
  }

  void _loadEpisode(Episode episode) {
    if (_editing || _exporting || _diagnosing) {
      _pendingEpisodeChange = episode;
      return;
    }
    final generation = ++_loadGeneration;
    _displayEpisode = episode;
    _indexFocus =
        widget.episode.guid == episode.guid && widget.initialPassageId != null;
    _localEdition = _editionSourceKey;
    _pendingEpisodeChange = null;
    _showOriginal = false;
    _searchController.clear();
    _search = TranscriptSearch('');
    _selectedCueId = null;
    _scrollReset++;
    final previousEdits = _edits;
    previousEdits?.removeListener(_editsChanged);
    previousEdits?.dispose();
    _edits = null;
    _editPlayer?.unregisterTranscriptEdit(this);
    final transcript = _load(
      episode,
      widget.loadTranscript,
      widget.editStore,
      generation,
    );
    setState(() {
      _transcript = transcript;
    });
  }

  Future<EpisodeTranscript> _load(
    Episode episode,
    Future<EpisodeTranscript> Function(String guid) loadTranscript,
    TranscriptEditStore? editStore,
    int generation,
  ) async {
    final baseline = await loadTranscript(episode.guid);
    if (!mounted || generation != _loadGeneration) return baseline;
    final edits = TranscriptEdits(
      baseline: baseline,
      store:
          editStore ??
          (LocalPreparedEpisodes.forGuid(episode.guid)?.readOnly == true
              ? ReadOnlyTranscriptEditStore()
              : FileTranscriptEditStore(
                  editionKey: LocalPreparedEpisodes.forGuid(episode.guid)
                      ?.edition,
                )),
    );
    await edits.load();
    if (!mounted || generation != _loadGeneration) {
      edits.dispose();
      return baseline;
    }
    edits.addListener(_editsChanged);
    // The toolbar is outside FutureBuilder and must reflect load completion too.
    setState(() {
      _edits = edits;
    });
    _bindPlayerEdit();
    return baseline;
  }

  void _retryLoad() => _loadEpisode(_displayEpisode);

  void _editsChanged() {
    if (mounted) {
      setState(() {});
      if (_edits?.ready == true) {
        _editPlayer?.setTranscriptContext(_edits!.current, _edits!.syncOffset);
      }
      _editPlayer?.refreshTranscriptEdit();
    }
  }

  Future<void> _editCue(TranscriptCue cue) async {
    if (LocalPreparedEpisodes.forGuid(_displayEpisode.guid)?.readOnly == true) {
      return;
    }
    final edits = _edits;
    final episode = _displayEpisode;
    if (edits == null ||
        !edits.ready ||
        edits.busy ||
        edits.conflict ||
        _exporting ||
        _editing) {
      return;
    }
    final player = _editPlayer;
    if (player?.busy == true) return;
    setState(() {
      _editing = true;
      _selectedCueId = cue.id;
    });
    player?.refreshTranscriptEdit();
    PlaybackBookmark? bookmark;
    bool? saved;
    try {
      if (player?.output == PlaybackOutput.audioPlayer) {
        bookmark = await player!.pauseForEditing();
        if (!mounted || bookmark == null) return;
      }
      if (!mounted) return;
      saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            TranscriptEditorDialog(episode: episode, cue: cue, edits: edits),
      );
    } finally {
      if (bookmark != null) await player!.restoreAfterEditing(bookmark);
      if (mounted) {
        setState(() {
          _editing = false;
          _selectedCueId = null;
          if (saved == true) _showOriginal = false;
        });
        player?.refreshTranscriptEdit();
        final pendingEpisode = _pendingEpisodeChange;
        if (pendingEpisode != null) _loadEpisode(pendingEpisode);
      }
    }
  }

  Future<void> _export() async {
    final edits = _edits;
    if (edits == null || !edits.ready || edits.busy || _exporting) return;
    setState(() => _exporting = true);
    _editPlayer?.refreshTranscriptEdit();
    try {
      final timingDescription = edits.current.audioIdentity == null
          ? 'VTT and SRT keep the original passage timestamps.'
          : 'VTT and SRT use the aligned passage timestamps for the fixed audio edition.';
      final continueExport = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export timing'),
          content: Text(
            '$timingDescription Only the JSON export includes this app’s '
            'playback timing adjustment; other caption players will not apply it automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue exporting'),
            ),
          ],
        ),
      );
      if (continueExport != true || !mounted) return;
      final files = transcriptExportFiles(
        edits,
        'episode-${_displayEpisode.number ?? 'transcript'}-reviewed',
      );
      final message = await widget.exportTranscript(files);
      if (mounted && message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The transcript could not be exported. Your saved corrections are safe.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
        _editPlayer?.refreshTranscriptEdit();
        final pendingEpisode = _pendingEpisodeChange;
        if (pendingEpisode != null) _loadEpisode(pendingEpisode);
      }
    }
  }

  @override
  void dispose() {
    LocalPreparedEpisodes.changes.removeListener(_preparedEditionChanged);
    final player = _editPlayer;
    if (_route != null) playbackRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      player?.unregisterTranscriptEdit(this);
    });
    _edits?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateSearch(String query) {
    setState(() {
      _search = TranscriptSearch(query);
      _selectedCueId = null;
    });
    _scrollToTop();
  }

  void _scrollToTop() {
    setState(() => _scrollReset++);
    _editPlayer?.refreshTranscriptEdit();
  }

  void _selectForEditing(TranscriptCue cue) {
    if (LocalPreparedEpisodes.forGuid(_displayEpisode.guid)?.readOnly == true) {
      return;
    }
    if (_edits?.ready != true ||
        _edits!.busy ||
        _edits!.conflict ||
        _exporting ||
        _editing) {
      return;
    }
    setState(() => _selectedCueId = _selectedCueId == cue.id ? null : cue.id);
    _editPlayer?.refreshTranscriptEdit();
  }

  void _playPassage(TranscriptCue cue) {
    setState(() {
      _selectedCueId = null;
      _indexFocus = false;
    });
    _editPlayer?.refreshTranscriptEdit();
    _editPlayer?.playEpisode(
      _displayEpisode,
      from: _edits?.audioStart(cue) ?? cue.start,
    );
  }

  Widget _passageText(String text, BuildContext context) {
    if (!_search.isActive) return Text(text);
    final spans = <TextSpan>[];
    var end = 0;
    final colors = Theme.of(context).colorScheme;
    for (final match in _search.matches(text)) {
      if (match.start > end) {
        spans.add(TextSpan(text: text.substring(end, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            backgroundColor: colors.tertiaryContainer,
            color: colors.onTertiaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      end = match.end;
    }
    if (end < text.length) spans.add(TextSpan(text: text.substring(end)));
    return Text.rich(TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackScope.maybeOf(context);
    final episode = _displayEpisode;
    final canSeek =
        playback != null &&
        playback.preferencesReady &&
        playback.output == PlaybackOutput.audioPlayer &&
        !playback.busy &&
        EpisodeAudio.sourceFor(episode) != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript'),
        actions: [
          IconButton(
            tooltip: 'Transcript timing diagnostics',
            icon: const Icon(Icons.timer_outlined),
            onPressed:
                _edits?.ready == true &&
                    !_edits!.busy &&
                    !_editing &&
                    !_exporting &&
                    !_diagnosing &&
                    playback != null
                ? _openTimingDiagnostics
                : null,
          ),
          IconButton(
            tooltip: 'Correction history',
            icon: const Icon(Icons.history),
            onPressed: _edits?.ready == true && !_exporting
                ? () => showTranscriptHistory(context, _edits!)
                : null,
          ),
          IconButton(
            tooltip: 'Export reviewed transcript',
            icon: const Icon(Icons.ios_share),
            onPressed:
                _edits?.ready == true &&
                    !_edits!.busy &&
                    !_edits!.conflict &&
                    !_exporting
                ? _export
                : null,
          ),
        ],
      ),
      body: FutureBuilder<EpisodeTranscript>(
        future: _transcript,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('The transcript could not be loaded.'),
                  TextButton(
                    onPressed: _retryLoad,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            );
          }
          if (snapshot.data == null ||
              (snapshot.connectionState == ConnectionState.waiting &&
                  _edits == null)) {
            return const Center(child: CircularProgressIndicator());
          }
          final transcript = _edits?.current ?? snapshot.data!;
          final currentCue =
              playback != null &&
                  playback.output == PlaybackOutput.audioPlayer &&
                  playback.episode?.guid == episode.guid
              ? transcriptCueAt(
                  transcript.cues,
                  playback.position + (_edits?.syncOffset ?? Duration.zero),
                )
              : null;
          final followingCue = playback?.playing == true ? currentCue : null;
          final matches = _search.filter(
            transcript.cues,
            original: _showOriginal,
          );
          final cues = [...matches];
          var includePlaying = false;
          if (followingCue != null &&
              !matches.any((cue) => cue.id == followingCue.id)) {
            includePlaying = true;
            cues.add(followingCue);
            cues.sort((a, b) => a.start.compareTo(b.start));
          }
          final followIndex =
              followingCue == null || _selectedCueId != null || _indexFocus
              ? null
              : cues.indexWhere((cue) => cue.id == followingCue.id) + 1;
          return Column(
            children: [
              if (_indexFocus)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text('Opened passage ${widget.initialPassageId}'),
                    TextButton(
                      onPressed: () => setState(() => _indexFocus = false),
                      child: const Text('Follow audio'),
                    ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _searchController,
                  onChanged: _updateSearch,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: 'Search transcript',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear transcript search',
                            onPressed: () {
                              _searchController.clear();
                              _updateSearch('');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              if (_search.isActive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      matches.isEmpty
                          ? 'No matching passages'
                          : '${matches.length} matching '
                                '${matches.length == 1 ? 'passage' : 'passages'}',
                      semanticsLabel: matches.isEmpty
                          ? 'No matching passages'
                          : '${matches.length} matching passages',
                    ),
                  ),
                ),
              if (includePlaying)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    'Also showing the playing passage, which does not match the search.',
                  ),
                ),
              if (_edits?.loadError != null || _edits?.conflict == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_edits?.loadError != null) Text(_edits!.loadError!),
                      if (_edits?.conflict == true)
                        const Text(
                          'Saved corrections changed in another editor. '
                          'Reload before editing or exporting again.',
                        ),
                      TextButton(
                        onPressed: _edits!.busy ? null : _edits!.load,
                        child: Text(
                          _edits!.conflict
                              ? 'Reload saved corrections'
                              : 'Retry saved corrections',
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TranscriptPassageList(
                  key: ValueKey('transcript-${episode.guid}'),
                  followIndex: followIndex,
                  resetToken: _scrollReset,
                  initialIndex:
                      widget.episode.guid == episode.guid &&
                          widget.initialPassageId != null &&
                          cues.any((cue) => cue.id == widget.initialPassageId)
                      ? cues.indexWhere(
                              (cue) => cue.id == widget.initialPassageId,
                            ) +
                            1
                      : null,
                  itemCount: cues.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            episode.title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(transcript.label),
                          if (_edits?.history.isNotEmpty == true)
                            const Text(
                              'Includes your local corrections. '
                              'These have not been automatically checked against the audio.',
                            ),
                          const SizedBox(height: 8),
                          Text(transcript.note),
                          const SizedBox(height: 8),
                          const Text(
                            'Flagged passages need further review. '
                            'Select a passage to play from that point with the Audio player. '
                            'Choose Audio player in Settings to enable seeking.',
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Show original machine transcript',
                            ),
                            value: _showOriginal,
                            onChanged: (value) {
                              setState(() {
                                _showOriginal = value;
                                _selectedCueId = null;
                              });
                              _scrollToTop();
                            },
                          ),
                          const Divider(),
                        ],
                      );
                    }
                    final cue = cues[index - 1];
                    final playingCue = currentCue?.id == cue.id;
                    final editingCue = _selectedCueId == cue.id;
                    final openedCue =
                        _indexFocus &&
                        widget.episode.guid == episode.guid &&
                        widget.initialPassageId == cue.id;
                    final colors = Theme.of(context).colorScheme;
                    return GestureDetector(
                      onSecondaryTapUp: (_) => _selectForEditing(cue),
                      onLongPress: () => _selectForEditing(cue),
                      child: ListTile(
                        key: ValueKey('transcript-cue-${cue.id}'),
                        selected: playingCue || editingCue || openedCue,
                        selectedTileColor: editingCue
                            ? colors.tertiaryContainer
                            : openedCue
                            ? colors.primaryContainer
                            : colors.secondaryContainer,
                        shape: editingCue
                            ? RoundedRectangleBorder(
                                side: BorderSide(
                                  color: colors.tertiary,
                                  width: 2,
                                ),
                              )
                            : null,
                        isThreeLine: false,
                        leading: Text('${cue.timeLabel}\nPassage ${cue.id}'),
                        trailing: editingCue
                            ? IconButton(
                                tooltip: 'Edit passage ${cue.id}',
                                icon: const Icon(Icons.edit),
                                onPressed: _canEditSelected()
                                    ? _openSelected
                                    : null,
                              )
                            : null,
                        title: _passageText(
                          _showOriginal ? cue.originalText : cue.text,
                          context,
                        ),
                        subtitle: cue.reviewNotes.isEmpty
                            ? null
                            : Text(
                                'Needs review: ${cue.reviewNotes.join(' ')}',
                              ),
                        onTap: playback != null && canSeek
                            ? () => _playPassage(cue)
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
