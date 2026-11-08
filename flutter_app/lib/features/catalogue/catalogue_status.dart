import 'package:flutter/material.dart';

import 'catalogue_manager.dart';

class CatalogueStatus extends StatelessWidget {
  const CatalogueStatus({required this.manager, super.key});
  final CatalogueManager manager;

  @override
  Widget build(BuildContext context) {
    if (manager.notice == null && manager.details == null) {
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
