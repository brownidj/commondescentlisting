import 'dart:async';
import 'dart:convert';

import 'package:common_descent_listing/data/catalogue_repository.dart';
import 'package:common_descent_listing/data/local_catalogue.dart';
import 'package:common_descent_listing/features/catalogue/catalogue_manager.dart';
import 'package:common_descent_listing/features/catalogue/catalogue_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String yaml(String title) => jsonEncode({
  'podcast': {'title': title},
  'segments': [
    {'guid': title, 'episode_title': title, 'segment_type': 'Episode'},
  ],
});

class Source implements CatalogueSource {
  Source(this.contents);
  final String contents;
  @override
  String get name => 'Bundled fixture';
  @override
  Future<String> load() async => contents;
}

class Store implements CatalogueStore {
  String? saved;
  bool failSave = false;
  bool failClear = false;
  @override
  Future<String?> read() async => saved;
  @override
  Future<void> save(String yaml) async {
    if (failSave) throw StateError('disk full');
    saved = yaml;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('permission denied');
    saved = null;
  }
}

class PausingStore extends Store {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> save(String yaml) async {
    started.complete();
    await release.future;
    await super.save(yaml);
  }
}

void main() {
  for (final startupFailure in [false, true]) {
    testWidgets(
      'technical details expand repeatedly (startupFailure=$startupFailure)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(900, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final manager = CatalogueManager(
          bundled: Source(startupFailure ? '[' : yaml('Bundled')),
          store: Store(),
          pick: () async => '[',
        );
        addTearDown(manager.dispose);
        await tester.pumpWidget(
          MaterialApp(home: CatalogueShell(manager: manager)),
        );
        await tester.pumpAndSettle();
        if (!startupFailure) {
          await tester.tap(find.byTooltip('Import YAML catalogue'));
          await tester.pumpAndSettle();
        }
        final tile = find.text('Technical details');
        for (var index = 0; index < 3; index++) {
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(find.textContaining('invalid YAML'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  test(
    'candidate remains inactive until its persistent save completes',
    () async {
      final store = PausingStore()..saved = yaml('Previous');
      final manager = CatalogueManager(
        bundled: Source(yaml('Bundled')),
        store: store,
        pick: () async => yaml('Next'),
      );
      addTearDown(manager.dispose);
      await manager.initialise();
      final previous = manager.current;
      final pending = manager.importYaml();
      await store.started.future;
      expect(manager.current, same(previous));
      expect(store.saved, yaml('Previous'));
      expect(manager.busy, isTrue);
      store.release.complete();
      await pending;
      expect(manager.current!.podcast.title, 'Next');
      expect(manager.busy, isFalse);
    },
  );

  testWidgets('toolbar import and reset update origin and browsing data', (
    tester,
  ) async {
    final store = Store();
    final manager = CatalogueManager(
      bundled: Source(yaml('Bundled')),
      store: store,
      pick: () async => yaml('Imported'),
    );
    addTearDown(manager.dispose);
    await tester.pumpWidget(
      MaterialApp(home: CatalogueShell(manager: manager)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('episode-Bundled')), findsOneWidget);
    await tester.tap(find.byTooltip('Import YAML catalogue'));
    await tester.pumpAndSettle();
    expect(find.text('Saved local catalogue'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-Imported')), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-Bundled')), findsNothing);
    await tester.tap(find.byTooltip('Reset to bundled catalogue'));
    await tester.pumpAndSettle();
    expect(find.text('Bundled catalogue'), findsOneWidget);
    expect(find.byKey(const ValueKey('episode-Bundled')), findsOneWidget);
    expect(store.saved, isNull);
  });

  test(
    'import persists before activation; restart restores and reset is durable',
    () async {
      final store = Store();
      final manager = CatalogueManager(
        bundled: Source(yaml('Bundled')),
        store: store,
        pick: () async => yaml('Imported'),
      );
      addTearDown(manager.dispose);
      await manager.initialise();
      expect(manager.imported, isFalse);
      await manager.importYaml();
      expect(manager.current!.podcast.title, 'Imported');
      expect(store.saved, yaml('Imported'));
      final restarted = CatalogueManager(
        bundled: Source(yaml('Bundled')),
        store: store,
        pick: () async => null,
      );
      addTearDown(restarted.dispose);
      await restarted.initialise();
      expect(restarted.current!.podcast.title, 'Imported');
      expect(restarted.imported, isTrue);
      await restarted.reset();
      expect(store.saved, isNull);
      expect(restarted.current!.podcast.title, 'Bundled');
      await restarted.initialise();
      expect(restarted.imported, isFalse);
    },
  );

  test('cancel, invalid input, oversized input and failed save keep current and disk', () async {
    final store = Store()..saved = yaml('Previous');
    String? picked;
    final manager = CatalogueManager(
      bundled: Source(yaml('Bundled')),
      store: store,
      pick: () async => picked,
    );
    addTearDown(manager.dispose);
    await manager.initialise();
    final previous = manager.current;
    final revision = manager.revision;
    await manager.importYaml();
    expect(manager.current, same(previous));
    expect(manager.revision, revision);
    for (final input in ['[', 'x' * (catalogueByteLimit + 1)]) {
      picked = input;
      await manager.importYaml();
      expect(manager.current, same(previous));
      expect(store.saved, yaml('Previous'));
      expect(manager.details, isNotNull);
    }
    picked = yaml('Next');
    store.failSave = true;
    await manager.importYaml();
    expect(manager.current, same(previous));
    expect(store.saved, yaml('Previous'));
  });

  test(
    'corrupt saved data falls back; reset failure retains last valid import',
    () async {
      final store = Store()..saved = '[';
      final manager = CatalogueManager(
        bundled: Source(yaml('Bundled')),
        store: store,
        pick: () async => yaml('Imported'),
      );
      addTearDown(manager.dispose);
      await manager.initialise();
      expect(manager.current!.podcast.title, 'Bundled');
      expect(manager.notice, contains('saved catalogue could not be loaded'));
      expect(manager.details, isNotNull);
      await manager.importYaml();
      store.failClear = true;
      final previous = manager.current;
      await manager.reset();
      expect(manager.current, same(previous));
      expect(store.saved, yaml('Imported'));
    },
  );

  test(
    'pending picker serialises operations and cancellation releases busy',
    () async {
      final store = Store();
      final picker = Completer<String?>();
      final manager = CatalogueManager(
        bundled: Source(yaml('Bundled')),
        store: store,
        pick: () => picker.future,
      );
      addTearDown(manager.dispose);
      await manager.initialise();
      final revision = manager.revision;
      final pending = manager.importYaml();
      expect(manager.busy, isTrue);
      await manager.reset();
      await manager.importYaml();
      expect(manager.revision, revision);
      picker.complete(null);
      await pending;
      expect(manager.busy, isFalse);
      expect(manager.revision, revision);
    },
  );
}
