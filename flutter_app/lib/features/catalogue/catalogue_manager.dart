import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/catalogue_repository.dart';
import '../../data/local_catalogue.dart';
import '../../models/catalogue.dart';
import '../../services/catalogue_picker.dart';

/// Serialises catalogue operations; only fully saved candidates become active.
class CatalogueManager extends ChangeNotifier {
  CatalogueManager({
    required this.bundled,
    required this.store,
    required this.pick,
  });
  final CatalogueSource bundled;
  final CatalogueStore store;
  final CataloguePicker pick;

  Catalogue? current;
  bool busy = false;
  bool imported = false;
  String? notice;
  String? details;
  int revision = 0;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _activate(Catalogue catalogue, {required bool local}) {
    current = catalogue;
    imported = local;
    revision++;
  }

  Future<void> initialise() async {
    if (busy) return;
    busy = true;
    notice = null;
    details = null;
    _notify();
    String? savedError;
    try {
      try {
        final saved = await store.read();
        if (saved != null) {
          final catalogue = await CatalogueRepository(
            source: LocalCatalogueSource(saved, name: 'Saved local catalogue'),
          ).load();
          _activate(catalogue, local: true);
          return;
        }
      } catch (error) {
        savedError = '$error';
      }
      final catalogue = await CatalogueRepository(source: bundled).load();
      _activate(catalogue, local: false);
      if (savedError != null) {
        notice = 'The saved catalogue could not be loaded. Using bundled data.';
        details = savedError;
      }
    } catch (error) {
      notice = 'The catalogue could not be loaded. Please try again.';
      details = [?savedError, '$error'].join('\n');
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importYaml() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      final yaml = await pick();
      if (yaml == null) {
        return; // Cancellation retains data and existing notice.
      }
      if (utf8.encode(yaml).length > catalogueByteLimit) {
        throw const FormatException(
          'The YAML file exceeds the 5 MiB import limit.',
        );
      }
      final candidate = await CatalogueRepository(
        source: LocalCatalogueSource(yaml),
      ).load();
      await store.save(yaml);
      _activate(candidate, local: true);
      notice = 'Imported catalogue saved for future launches.';
      details = null;
    } catch (error) {
      notice = 'Import failed. The current catalogue was kept.';
      details = '$error';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> importServerYaml(String yaml) async {
    if (busy) throw StateError('Catalogue is busy; try again.');
    if (utf8.encode(yaml).length > catalogueByteLimit) {
      throw const FormatException('Server catalogue exceeds 5 MiB.');
    }
    final candidate = await CatalogueRepository(
      source: LocalCatalogueSource(yaml, name: 'Server library catalogue'),
    ).load();
    await store.save(yaml);
    if (_disposed) return;
    _activate(candidate, local: true);
    notice = 'Library catalogue saved for offline browsing.';
    _notify();
  }

  Future<void> reset() async {
    if (busy) return;
    busy = true;
    _notify();
    try {
      // Validate bundled data before removing the persisted selection.
      final candidate = await CatalogueRepository(source: bundled).load();
      await store.clear();
      _activate(candidate, local: false);
      notice = 'Using the bundled catalogue. The saved import was removed.';
      details = null;
    } catch (error) {
      notice = 'Reset failed. The current catalogue was kept.';
      details = '$error';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
