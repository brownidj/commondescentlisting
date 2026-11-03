import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'index_store.dart';

Future<String?> importIndexRegistry() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Index registry JSON',
        extensions: ['json'],
        uniformTypeIdentifiers: ['public.json'],
      ),
    ],
  );
  if (file == null) {
    return null;
  }
  if (await file.length() > FileIndexRegistryStore.byteLimit) {
    throw const FormatException('Index registry exceeds 20 MiB.');
  }
  return file.readAsString();
}

Future<String> exportIndexRegistry(String source) async {
  if (Platform.isIOS) {
    await Clipboard.setData(ClipboardData(text: source));
    return 'Index registry copied to clipboard for backup or transfer.';
  }
  try {
    final location = await getSaveLocation(
      suggestedName: 'transcript-indexes.json',
    );
    if (location == null) {
      return 'Export cancelled.';
    }
    await XFile.fromData(
      Uint8List.fromList(utf8.encode(source)),
      mimeType: 'application/json',
      name: 'transcript-indexes.json',
    ).saveTo(location.path);
    return 'Index registry exported.';
  } on MissingPluginException {
    await Clipboard.setData(ClipboardData(text: source));
    return 'Index registry copied to clipboard.';
  }
}
