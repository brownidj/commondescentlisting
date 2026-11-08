import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../app_identity.dart';
import '../../data/bundled_catalogue.dart';
import '../../data/podcast_feed_catalogue.dart';
import '../../services/library_connection.dart';
import '../../data/local_prepared_episodes.dart';
import '../../data/file_catalogue_store.dart';
import '../../services/catalogue_picker.dart';
import '../../widgets/catalogue_message.dart';
import '../../widgets/playback_scope.dart';
import '../../widgets/playback_settings_dialog.dart';
import '../episodes/episode_browser.dart';
import '../preparation/preparation_controller.dart';
import '../preparation/http_preparation_backend.dart';
import '../preparation/preparation_scope.dart';
import '../preparation/preparation_dialog.dart';
import '../news/news_browser.dart';
import '../indexes/index_browser.dart';
import '../indexes/index_controller.dart';
import 'catalogue_manager.dart';
import 'catalogue_status.dart';

class CatalogueShell extends StatefulWidget {
  const CatalogueShell({this.manager, this.preparation, super.key});
  final CatalogueManager? manager;
  final PreparationController? preparation;

  @override
  State<CatalogueShell> createState() => _CatalogueShellState();
}

class _CatalogueShellState extends State<CatalogueShell> {
  late final CatalogueManager _manager;
  late final PreparationController _preparation;
  var _bucket = PageStorageBucket();
  int _revision = 0;
  int _selectedIndex = 0;
  KnowledgeIndexController? _knowledge;

  @override
  void initState() {
    super.initState();
    _preparation =
        widget.preparation ?? PreparationController(HttpPreparationBackend());
    LocalPreparedEpisodes.changes.addListener(_preparedChanged);
    _preparation.connect();
    _manager =
        widget.manager ??
        CatalogueManager(
          bundled: BundledCatalogue(),
          store: FileCatalogueStore(),
          pick: pickCatalogueYaml,
          refresh: (current, progress) async {
            progress('Checking library connection', null);
            final library = LibraryConnection.instance;
            final yaml = await library.restore();
            if (yaml != null) {
              return yaml;
            }
            if (library.error != null) {
              throw StateError(library.error!);
            }
            return PodcastFeedCatalogue().refresh(current, progress);
          },
        );
    _manager.addListener(_changed);
    _initialiseLibrary();
  }

  Future<void> _initialiseLibrary() async {
    await _manager.initialise();
  }

  void _preparedChanged() {
    if (!mounted) return;
    PlaybackScope.maybeOf(context)?.refreshPreparedEdition();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_revision != _manager.revision) {
        _revision = _manager.revision;
        _knowledge?.dispose();
        _knowledge = null;
        _bucket = PageStorageBucket();
      }
    });
  }

  @override
  void dispose() {
    LocalPreparedEpisodes.changes.removeListener(_preparedChanged);
    _manager.removeListener(_changed);
    if (widget.manager == null) _manager.dispose();
    if (widget.preparation == null) _preparation.dispose();
    _knowledge?.dispose();
    super.dispose();
  }

  Widget _content() {
    final catalogue = _manager.current;
    if (catalogue == null) {
      if (_manager.busy) {
        return const CatalogueMessage(
          icon: Icons.folder_open_outlined,
          title: 'Loading catalogue',
          message: 'Reading local data. No internet is required.',
          action: CircularProgressIndicator(
            semanticsLabel: 'Loading catalogue',
          ),
        );
      }
      return CatalogueMessage(
        icon: Icons.error_outline,
        title: 'The catalogue could not be loaded',
        message: _manager.notice ?? 'Please retry or import a valid YAML file.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _manager.initialise,
              child: const Text('Retry'),
            ),
            if (_manager.details != null)
              ExpansionTile(
                maintainState: true,
                key: const PageStorageKey('startup-error-expansion'),
                title: const Text('Technical details'),
                children: [Text(_manager.details!)],
              ),
          ],
        ),
      );
    }
    final knowledge = _knowledge ??= KnowledgeIndexController(
      catalogue: catalogue,
    );
    return Column(
      children: [
        CatalogueStatus(manager: _manager),
        ListenableBuilder(
          listenable: _preparation,
          builder: (context, _) {
            final job = _preparation.job;
            if (job?.active != true) return const SizedBox.shrink();
            return ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(job!.stage),
              subtitle: LinearProgressIndicator(value: job.fraction),
              trailing: TextButton(
                onPressed: () => showPreparationProgress(context, _preparation),
                child: const Text('Preparation progress'),
              ),
            );
          },
        ),
        if (_manager.busy)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_manager.updateStage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Text(_manager.updateStage!),
                ),
              LinearProgressIndicator(
                value: _manager.updateProgress,
                semanticsLabel: _manager.updateStage ?? 'Updating catalogue',
              ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: ExcludeFocus(
            excluding: _manager.busy,
            child: AbsorbPointer(
              absorbing: _manager.busy,
              child: PageStorage(
                bucket: _bucket,
                child: IndexedStack(
                  key: ValueKey(_revision),
                  index: _selectedIndex,
                  children: [
                    EpisodeBrowser(
                      catalogue: catalogue,
                      indexController: knowledge,
                      active: _selectedIndex == 0,
                    ),
                    NewsBrowser(catalogue: catalogue),
                    IndexBrowser(
                      catalogue: catalogue,
                      controller: knowledge,
                      catalogueLabel: _manager.imported
                          ? 'Saved local catalogue'
                          : 'Bundled catalogue',
                      active: _selectedIndex == 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = PlaybackScope.maybeOf(context);
    final catalogue = _manager.current;
    final countStyle =
        Theme.of(context).textTheme.headlineSmall ??
        const TextStyle(fontSize: 24);
    return PreparationScope(
      controller: _preparation,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/branding/app-icon.png',
                      width: 28,
                      height: 28,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        text: appName,
                        children: [
                          if (catalogue != null)
                            TextSpan(
                              text:
                                  ' - ${catalogue.episodes.length} episodes and ${catalogue.newsCount} news',
                              style: countStyle.copyWith(
                                fontSize: (countStyle.fontSize ?? 24) - 4,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS)
                  IconButton(
                    tooltip: 'Preparation progress',
                    icon: const Icon(Icons.pending_actions_outlined),
                    onPressed: () =>
                        showPreparationProgress(context, _preparation),
                  ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: playback == null
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) => PlaybackSettingsDialog(
                            controller: playback,
                            onLibraryCatalogue: _manager.importServerYaml,
                          ),
                        ),
                ),
                IconButton(
                  tooltip: 'Import YAML catalogue',
                  icon: const Icon(Icons.file_open_outlined),
                  onPressed: _manager.busy ? null : _manager.importYaml,
                ),
                IconButton(
                  tooltip: 'Reset to bundled catalogue',
                  icon: const Icon(Icons.restore),
                  onPressed: _manager.busy ? null : _manager.reset,
                ),
              ],
            ),
            body: SafeArea(
              child: Row(
                children: [
                  if (wide) ...[
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      labelType: NavigationRailLabelType.all,
                      onDestinationSelected: (index) =>
                          setState(() => _selectedIndex = index),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.library_books_outlined),
                          label: Text('Episodes'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.newspaper_outlined),
                          label: Text('News'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.manage_search_outlined),
                          label: Text('Indexes'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(child: _content()),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.library_books_outlined),
                        label: 'Episodes',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.newspaper_outlined),
                        label: 'News',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.manage_search_outlined),
                        label: 'Indexes',
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
