import 'preparation_models.dart';

abstract class PreparationBackend {
  Future<void> connect();
  Future<void> configure();
  Future<List<PreparationModel>> models();
  Future<PreparationEpisode> inspect(String guid);
  Future<PreparationJob?> currentJob();
  Future<PreparationJob> start({
    required String guid,
    required String model,
    required bool replace,
    required bool redownload,
    bool refineChatGPT = false,
    bool enrichmentOnly = false,
    String? retryJob,
  });
  Future<PreparationJob> job(String id);
  Future<void> cancel(String id);
  Future<void> refreshLibrary();
  void dispose();
}
