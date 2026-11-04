import 'dart:convert';

import 'package:common_descent_listing/features/indexes/index_details.dart';
import 'package:common_descent_listing/features/indexes/index_details_panel.dart';
import 'package:common_descent_listing/features/indexes/index_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Crossref shows ordered authors and date caveat with metadata', (
    tester,
  ) async {
    final entity = IndexEntity(
      id: 'paper',
      kind: IndexKind.paper,
      name: 'Source title',
      year: 2017,
      publication: 'Source Journal',
      details: IndexDetails(
        bibliography: jsonEncode({
          'status': 'source_confirmed',
          'title': 'Source title',
          'authors': [
            {'given': 'Jane', 'family': 'First'},
            {'given': 'John', 'family': 'Second'},
          ],
          'publication_date_note': 'Issue date is after the episode.',
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: IndexDetailsPanel(entity: entity, showReviewDetails: false),
          ),
        ),
      ),
    );
    expect(find.text('Publication details — Crossref'), findsOneWidget);
    expect(find.text('Authors: Jane First; John Second'), findsOneWidget);
    expect(find.text('Source Journal · 2017'), findsOneWidget);
    expect(find.text('Issue date is after the episode.'), findsOneWidget);
    await tester.tap(find.text('Full publication metadata'));
    await tester.pumpAndSettle();
    expect(find.text(entity.details!.bibliography), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unresolved candidate metadata stays explicitly unconfirmed', (
    tester,
  ) async {
    final entity = IndexEntity(
      id: 'pending',
      kind: IndexKind.paper,
      name: 'Unresolved',
      details: IndexDetails(
        bibliography: jsonEncode({
          'status': 'unconfirmed_candidates',
          'candidates': [],
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IndexDetailsPanel(entity: entity)),
      ),
    );
    expect(find.text('Possible publications — unconfirmed'), findsOneWidget);
    expect(find.text('Publication details — Crossref'), findsNothing);
  });
}
