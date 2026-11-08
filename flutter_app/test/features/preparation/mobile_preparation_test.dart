import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:common_descent_listing/features/preparation/preparation_backend.dart';
import 'package:common_descent_listing/features/preparation/preparation_controller.dart';
import 'package:common_descent_listing/features/preparation/preparation_dialog.dart';
import 'package:common_descent_listing/features/preparation/preparation_platform.dart';
import 'package:common_descent_listing/models/catalogue.dart';

// Any worker access fails this test: mobile must stop before connecting.
class UnreachableBackend implements PreparationBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Mobile accessed the preparation worker.');
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$platform explains desktop transcription without a worker', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final controller = PreparationController(UnreachableBackend());
      addTearDown(controller.dispose);
      final episode = Episode(
        guid: 'sample',
        title: 'Sample',
        number: '1',
        segments: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showEpisodePreparation(context, episode, controller),
                child: const Text('Prepare'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Prepare'));
      await tester.pumpAndSettle();
      expect(find.text(mobileTranscriptionMessage), findsOneWidget);
      expect(controller.connected, isFalse);
      expect(controller.error, isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(mobileTranscriptionMessage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
