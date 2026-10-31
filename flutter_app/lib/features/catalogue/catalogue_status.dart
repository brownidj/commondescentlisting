import 'package:flutter/material.dart';

import 'catalogue_manager.dart';

class CatalogueStatus extends StatelessWidget {
  const CatalogueStatus({required this.manager, super.key});
  final CatalogueManager manager;

  @override
  Widget build(BuildContext context) {
    final catalogue = manager.current!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: SingleChildScrollView(
        key: const PageStorageKey('catalogue-status-scroll'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                manager.imported
                    ? 'Saved local catalogue'
                    : 'Bundled catalogue',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${catalogue.episodes.length} episodes • ${catalogue.newsCount} news records',
              ),
              if (manager.notice != null) Text(manager.notice!),
              if (manager.details != null)
                ExpansionTile(
                  key: const PageStorageKey('catalogue-status-error-expansion'),
                  title: const Text('Technical details'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(manager.details!),
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
