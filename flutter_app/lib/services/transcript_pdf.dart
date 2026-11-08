import '../features/preparation/http_preparation_backend.dart';

typedef TranscriptPdfExporter = Future<String> Function(
  String guid,
  List<String> passages,
);

Future<String> createTranscriptPdf(String guid, List<String> passages) async {
  final worker = HttpPreparationBackend();
  try {
    await worker.connect();
    return await worker.createTranscriptPdf(guid, passages);
  } finally {
    worker.dispose();
  }
}
