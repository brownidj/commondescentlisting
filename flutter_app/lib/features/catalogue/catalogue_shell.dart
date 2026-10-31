import 'package:flutter/material.dart';

import '../../data/bundled_catalogue.dart';
import '../../data/file_catalogue_store.dart';
import '../../services/catalogue_picker.dart';
import '../../widgets/catalogue_message.dart';
import '../episodes/episode_browser.dart';
import '../news/news_browser.dart';
import 'catalogue_manager.dart';
import 'catalogue_status.dart';

class CatalogueShell extends StatefulWidget {
  const CatalogueShell({this.manager, super.key});
  final CatalogueManager? manager;

  @override
  State<CatalogueShell> createState() => _CatalogueShellState();
}

class _CatalogueShellState extends State<CatalogueShell> {
  late final CatalogueManager _manager;
  var _bucket = PageStorageBucket();
  int _revision = 0;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _manager =
        widget.manager ??
        CatalogueManager(
          bundled: BundledCatalogue(),
          store: FileCatalogueStore(),
          pick: pickCatalogueYaml,
        );
    _manager.addListener(_changed);
    _manager.initialise();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_revision != _manager.revision) {
        _revision = _manager.revision;
        _bucket = PageStorageBucket();
      }
    });
  }

  @override
  void dispose() {
    _manager.removeListener(_changed);
    if (widget.manager == null) _manager.dispose();
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
    return Column(
      children: [
        CatalogueStatus(manager: _manager),
        if (_manager.busy)
          const LinearProgressIndicator(semanticsLabel: 'Updating catalogue'),
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
                    EpisodeBrowser(catalogue: catalogue),
                    NewsBrowser(catalogue: catalogue),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Common Descent Listing'),
            actions: [
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
                  ],
                ),
        );
      },
    );
  }
}
