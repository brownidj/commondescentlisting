import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_descent_listing/features/preparation/preparation_backend.dart';
import 'package:common_descent_listing/features/preparation/preparation_controller.dart';
import 'package:common_descent_listing/features/preparation/preparation_dialog.dart';
import 'package:common_descent_listing/features/preparation/preparation_models.dart';
import 'package:common_descent_listing/models/catalogue.dart';

const fixtureModels = [
  PreparationModel(
    id: 'small.en',
    bytes: 487614201,
    rank: 3,
    available: true,
    secondsPerAudioHour: 90,
    overheadSecondsPerAudioHour: 220,
    fixedSeconds: 10,
    downloadBytesPerSecond: 3000000,
  ),
  PreparationModel(
    id: 'medium.en',
    bytes: 1533774781,
    rank: 4,
    available: true,
    secondsPerAudioHour: 300,
    overheadSecondsPerAudioHour: 220,
    fixedSeconds: 10,
    downloadBytesPerSecond: 3000000,
  ),
  PreparationModel(
    id: 'large-v3',
    bytes: 3095033483,
    rank: 6,
    available: false,
    secondsPerAudioHour: 600,
    overheadSecondsPerAudioHour: 220,
    fixedSeconds: 10,
    downloadBytesPerSecond: 3000000,
  ),
];
final episode = Episode(
  guid: 'episode',
  title: 'Sample episode',
  number: '83',
  segments: const [],
);

class FakeBackend implements PreparationBackend {
  int starts = 0;
  bool enrichmentRequested = false;
  String? retriedJob;
  int cancellations = 0;
  bool? refinementRequested;
  final info = const PreparationEpisode(
    prepared: true,
    audioSeconds: 7200,
    durationEstimated: false,
    refinementAvailable: true,
    model: 'medium.en',
    sourceAvailable: true,
  );
  @override
  Future<void> connect() async {}
  @override
  Future<void> configure() async {}
  @override
  Future<List<PreparationModel>> models() async => List.of(fixtureModels);
  @override
  Future<PreparationEpisode> inspect(String guid) async => info;
  @override
  Future<PreparationJob?> currentJob() async => null;
  @override
  Future<PreparationJob> start({
    required String guid,
    required String model,
    required bool replace,
    required bool redownload,
    bool refineChatGPT = false,
    bool enrichmentOnly = false,
    String? retryJob,
  }) async {
    starts++;
    refinementRequested = refineChatGPT;
    enrichmentRequested = enrichmentOnly;
    retriedJob = retryJob;
    return const PreparationJob(
      id: 'job',
      guid: 'episode',
      state: 'running',
      stage: 'Transcribing',
      elapsedSeconds: 10,
      remainingSeconds: 100,
      fraction: .25,
    );
  }

  @override
  Future<PreparationJob> job(String id) async => const PreparationJob(
    id: 'job',
    guid: 'episode',
    state: 'running',
    stage: 'Encoding audio',
    elapsedSeconds: 15,
    remainingSeconds: 95,
    fraction: .5,
  );
  @override
  Future<void> cancel(String id) async {
    cancellations++;
  }

  @override
  Future<void> refreshLibrary() async {}
  @override
  void dispose() {}
}

void main() {
  testWidgets('ChatGPT refinement defaults on and can be turned off', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PreparationOptionsDialog(
          episode: episode,
          info: const PreparationEpisode(
            prepared: false,
            audioSeconds: 7200,
            durationEstimated: true,
            refinementAvailable: true,
          ),
          models: fixtureModels,
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );
    expect(find.textContaining('limit US\$0.50'), findsOneWidget);
    await tester.tap(find.text('Refine using ChatGPT'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });

  testWidgets(
    'missing refinement setup blocks paid option but allows local only',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PreparationOptionsDialog(
            episode: episode,
            info: const PreparationEpisode(
              prepared: false,
              audioSeconds: 7200,
              durationEstimated: true,
            ),
            models: fixtureModels,
          ),
        ),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Prepare'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Refine using ChatGPT'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Prepare'))
            .onPressed,
        isNotNull,
      );
    },
  );

  test('controller forwards explicit refinement choice', () async {
    final backend = FakeBackend();
    final controller = PreparationController(backend);
    addTearDown(controller.dispose);
    await controller.prepare(
      guid: 'episode',
      model: 'medium.en',
      replace: false,
      redownload: false,
      refineChatGPT: true,
    );
    expect(backend.refinementRequested, isTrue);
  });

  testWidgets('long failure details scroll without hiding Close', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PreparationController(FakeBackend());
    addTearDown(controller.dispose);
    controller.job = PreparationJob(
      id: 'failed',
      guid: 'episode',
      title: 'The Karoo Supergroup',
      state: 'failed',
      stage: 'Failed',
      elapsedSeconds: 1016,
      remainingSeconds: null,
      error: List.generate(100, (i) => 'Diagnostic line $i').join('\n'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => PreparationProgressDialog(controller: controller),
            ),
            child: const Text('Open progress'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open progress'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.text('Preparation stopped'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('No preserves a prepared episode and starts no job', (
    tester,
  ) async {
    final backend = FakeBackend();
    final controller = PreparationController(backend);
    await controller.connect();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showEpisodePreparation(context, episode, controller),
            child: const Text('Prepare'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Prepare'));
    await tester.pumpAndSettle();
    expect(find.text('Re-prepare episode?'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(backend.starts, 0);
    controller.dispose();
  });

  testWidgets(
    'upgrade offers larger models; redownload permits existing model',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PreparationOptionsDialog(
            episode: episode,
            info: const PreparationEpisode(
              prepared: true,
              audioSeconds: 7200,
              durationEstimated: false,
              refinementAvailable: true,
              model: 'medium.en',
            ),
            models: fixtureModels,
          ),
        ),
      );
      var dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.items!.map((item) => item.value), ['large-v3']);
      expect(find.textContaining('Estimated'), findsNWidgets(2));
      expect(find.textContaining('checksum-verified'), findsOneWidget);
      await tester.tap(find.text('Redownload'));
      await tester.pumpAndSettle();
      dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.items!.map((item) => item.value), [
        'small.en',
        'medium.en',
        'large-v3',
      ]);
    },
  );

  testWidgets(
    'new episode offers all models with medium.en selected and an estimate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PreparationOptionsDialog(
            episode: episode,
            info: const PreparationEpisode(
              prepared: false,
              audioSeconds: 7200,
              durationEstimated: true,
              refinementAvailable: true,
            ),
            models: fixtureModels,
          ),
        ),
      );
      final dropdown = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>),
      );
      expect(dropdown.items!.map((item) => item.value), [
        'small.en',
        'medium.en',
        'large-v3',
      ]);
      expect(dropdown.value, 'medium.en');
      expect(
        find.textContaining('assuming a two-hour episode'),
        findsOneWidget,
      );
    },
  );

  testWidgets('external enrichment warnings offer an index-only retry', (
    tester,
  ) async {
    final backend = FakeBackend();
    final controller = PreparationController(backend);
    controller.job = const PreparationJob(
      id: 'previous-job',
      guid: 'episode',
      model: 'medium.en',
      state: 'completed',
      stage: 'Ready',
      elapsedSeconds: 100,
      remainingSeconds: null,
      enrichmentSummary: {
        'state': 'partial',
        'enriched': 3,
        'unresolved': 2,
        'stale': 1,
        'duplicates_merged': 0,
        'warnings': ['GeoNames unavailable'],
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: PreparationProgressDialog(controller: controller)),
    );
    expect(find.text('GeoNames unavailable'), findsOneWidget);
    expect(find.textContaining('3 enriched'), findsOneWidget);
    final retry = find.text('Retry external enrichment');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    expect(backend.enrichmentRequested, isTrue);
    expect(backend.retriedJob, 'previous-job');
    expect(backend.refinementRequested, isFalse);
    controller.dispose();
  });

  testWidgets('progress shows measured stage fraction and cancellation', (
    tester,
  ) async {
    final backend = FakeBackend();
    final controller = PreparationController(backend);
    await controller.prepare(
      guid: 'episode',
      model: 'medium.en',
      replace: true,
      redownload: true,
    );
    await tester.pumpWidget(
      MaterialApp(home: PreparationProgressDialog(controller: controller)),
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Encoding audio'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .5,
    );
    await tester.tap(find.text('Cancel preparation'));
    await tester.pump();
    expect(backend.cancellations, 1);
    controller.dispose();
  });
}
