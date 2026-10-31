import 'package:file_selector/file_selector.dart';

import '../data/local_catalogue.dart';

typedef CataloguePicker = Future<String?> Function();

Future<String?> pickCatalogueYaml() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'YAML catalogue', extensions: ['yaml', 'yml']),
    ],
  );
  if (file == null) return null;
  if (await file.length() > catalogueByteLimit) {
    throw const FormatException(
      'The YAML file exceeds the 5 MiB import limit.',
    );
  }
  return readCatalogueBytes(file.openRead());
}
