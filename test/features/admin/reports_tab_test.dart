import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:garbanzo_ai/features/admin/widgets/reports_tab.dart';
import 'package:garbanzo_ai/features/reports/models/report.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

void main() {
  Report report(String id, {String status = 'open', String type = 'bug'}) =>
      Report(
        id: id,
        userId: 'user@example.com',
        type: type,
        title: 'Report $id',
        description: 'Description of $id',
        status: status,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );

  Future<void> pump(
    WidgetTester tester, {
    required Future<List<Report>> Function({String? status}) load,
    Future<Report> Function(String id, String status)? updateStatus,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
          body: ReportsTab(load: load, updateStatus: updateStatus),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists reports with status chips', (tester) async {
    await pump(
      tester,
      load: ({String? status}) async => [
        report('a'),
        report('b', status: 'closed', type: 'feature'),
      ],
    );

    expect(find.text('Report a'), findsOneWidget);
    expect(find.text('Report b'), findsOneWidget);
    expect(find.text('Closed'), findsWidgets); // filter segment + chip
  });

  testWidgets('shows diagnostic metadata only for automatic reports', (
    tester,
  ) async {
    final automatic = Report(
      id: 'auto',
      userId: 'user@example.com',
      type: 'bug',
      title: 'Stream error',
      description: 'traceback',
      metadata: {'platform': 'android', 'stack_trace': 'frame one'},
      conversationId: 'conversation-1',
      severity: 'error',
      source: 'frontend',
      status: 'open',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );
    await pump(tester, load: ({String? status}) async => [automatic]);

    await tester.tap(find.byKey(const ValueKey('report_tile_auto')));
    await tester.pumpAndSettle();

    expect(find.text('Open conversation'), findsOneWidget);
    expect(find.text('Stack trace'), findsOneWidget);
    expect(find.text('Diagnostic metadata'), findsOneWidget);
  });

  testWidgets('status filter reloads with the selected status', (tester) async {
    final requested = <String?>[];
    await pump(
      tester,
      load: ({String? status}) async {
        requested.add(status);
        return [if (status == null || status == 'open') report('a')];
      },
    );
    expect(requested, [null]);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('reports_status_filter')),
        matching: find.text('Closed'),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, [null, 'closed']);
    expect(find.text('No closed reports'), findsOneWidget);
  });

  testWidgets('changing status via the menu updates the row', (tester) async {
    await pump(
      tester,
      load: ({String? status}) async => [report('a')],
      updateStatus: (id, status) async => report(id, status: status),
    );

    await tester.tap(find.byKey(const ValueKey('report_status_menu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('In progress').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report_tile_a')),
        matching: find.text('In progress'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('under a filter, a report moved out of it disappears', (
    tester,
  ) async {
    await pump(
      tester,
      load: ({String? status}) async =>
          status == null || status == 'open' ? [report('a')] : [],
      updateStatus: (id, status) async => report(id, status: status),
    );

    // Filter to Open, then close the report — the row should vanish.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('reports_status_filter')),
        matching: find.text('Open'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Report a'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report_status_menu_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed').last);
    await tester.pumpAndSettle();

    expect(find.text('Report a'), findsNothing);
  });
}
