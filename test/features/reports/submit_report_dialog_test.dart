import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/features/reports/models/report.dart';
import 'package:garbanzo_ai/features/reports/widgets/submit_report_dialog.dart';

void main() {
  Report fakeReport({String type = 'bug'}) => Report(
    id: 'r1',
    userId: 'test@example.com',
    type: type,
    title: 't',
    description: 'd',
    status: 'open',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  // Opens the dialog as a real dialog route (so popping it on success leaves
  // the app's Scaffold in place for the confirmation snackbar).
  Future<void> pump(
    WidgetTester tester, {
    required Future<Report> Function({
      required String type,
      required String title,
      required String description,
    })
    submit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => SubmitReportDialog(submit: submit),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('submit stays disabled until both fields are filled', (
    tester,
  ) async {
    await pump(
      tester,
      submit: ({required type, required title, required description}) async =>
          fakeReport(),
    );

    final submitButton = find.byKey(const ValueKey('report_submit_button'));
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('report_title_field')),
      'Crash on send',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('report_description_field')),
      'Steps to reproduce…',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
  });

  testWidgets('submits trimmed fields with the selected type', (tester) async {
    String? sentType;
    String? sentTitle;
    String? sentDescription;
    await pump(
      tester,
      submit: ({required type, required title, required description}) async {
        sentType = type;
        sentTitle = title;
        sentDescription = description;
        return fakeReport(type: type);
      },
    );

    await tester.tap(find.text('Feature'));
    await tester.enterText(
      find.byKey(const ValueKey('report_title_field')),
      '  Dark mode  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('report_description_field')),
      'Please add it',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report_submit_button')));
    await tester.pumpAndSettle();

    expect(sentType, 'feature');
    expect(sentTitle, 'Dark mode');
    expect(sentDescription, 'Please add it');
    expect(find.text('Thanks! Your report was submitted.'), findsOneWidget);
  });

  testWidgets('a failed submit shows the error and re-enables the form', (
    tester,
  ) async {
    await pump(
      tester,
      submit: ({required type, required title, required description}) async {
        throw Exception('boom');
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('report_title_field')),
      't',
    );
    await tester.enterText(
      find.byKey(const ValueKey('report_description_field')),
      'd',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report_submit_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not submit'), findsOneWidget);
    final submitButton = find.byKey(const ValueKey('report_submit_button'));
    expect(tester.widget<FilledButton>(submitButton).onPressed, isNotNull);
  });
}
