import 'package:flutter/material.dart';

import 'catalogue_manager.dart';

class CatalogueStatus extends StatelessWidget {
  const CatalogueStatus({
    required this.manager,
    this.showSummary = true,
    super.key,
  });
  final CatalogueManager manager;
  final bool showSummary;

  @override
  Widget build(BuildContext context) {
    final catalogue = manager.current!;
    if (!showSummary && manager.notice == null && manager.details == null) {
      return const SizedBox.shrink();
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        key: const PageStorageKey('catalogue-status-scroll'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSummary)
                Text(
                  manager.imported
                      ? 'Saved local catalogue'
                      : 'Bundled catalogue',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              if (showSummary)
                Text(
                  '${catalogue.episodes.length} ${catalogue.episodes.length == 1 ? 'episode' : 'episodes'} '
                  '• ${catalogue.newsCount} news records',
                ),
              if (manager.notice != null) Text(manager.notice!),
              if (manager.details != null)
                ExpansionTile(
                  maintainState: true,
                  key: const PageStorageKey('catalogue-status-error-expansion'),
                  title: const Text('Technical details'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(manager.details!),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
