import 'package:flutter/material.dart';

import '../../data/bundled_catalogue.dart';
import '../../data/catalogue_repository.dart';
import '../../models/catalogue.dart';
import '../../widgets/catalogue_message.dart';

class CatalogueShell extends StatefulWidget {
  const CatalogueShell({super.key});

  @override
  State<CatalogueShell> createState() => _CatalogueShellState();
}

class _CatalogueShellState extends State<CatalogueShell> {
  final _catalogue = CatalogueRepository(source: BundledCatalogue());
  late Future<Catalogue> _source;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _source = _catalogue.load();
  }

  void _retry() {
    setState(() => _source = _catalogue.load());
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final content = FutureBuilder<Catalogue>(
          future: _source,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const CatalogueMessage(
                icon: Icons.folder_open_outlined,
                title: 'Loading bundled catalogue',
                message: 'Reading the local data. No internet is required.',
                action: CircularProgressIndicator(
                  semanticsLabel: 'Loading catalogue',
                ),
              );
            }
            if (snapshot.hasError) {
              return CatalogueMessage(
                icon: Icons.error_outline,
                title: 'The bundled catalogue could not be loaded',
                message: 'Please check the bundled data and try again.',
                action: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(onPressed: _retry, child: const Text('Retry')),
                    ExpansionTile(
                      title: const Text('Technical details'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText('${snapshot.error}'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }
            final catalogue = snapshot.requireData;
            return CatalogueMessage(
              icon: _selectedIndex == 0
                  ? Icons.library_books_outlined
                  : Icons.newspaper_outlined,
              title: _selectedIndex == 0 ? 'Episodes' : 'News',
              message:
                  '${catalogue.episodes.length} episodes and '
                  '${catalogue.segments.length} segments loaded '
                  '(${catalogue.newsCount} news records). '
                  '${_selectedIndex == 0 ? 'Episode browsing' : 'News browsing'} '
                  'will be added in a later phase.',
              action: const Text('Offline catalogue • Phase 2 data layer'),
            );
          },
        );

        return Scaffold(
          appBar: AppBar(title: const Text('Common Descent Listing')),
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
                Expanded(child: content),
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
