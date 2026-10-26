import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/providers/read_aloud_controller.dart';
import 'package:garbanzo_ai/features/chat/services/visual_ui_service.dart';
import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_answer.dart';
import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_components.dart';
import 'package:garbanzo_ai/features/chat/widgets/visual_answers/visual_layout.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

class _ReadAloud extends Mock implements ReadAloudController {}

class _Service extends VisualUIService {
  int submissions = 0;
  bool fail = false;
  final records = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> state(String conversationId, String callId) async => {
    'available': true, 'submissions': records,
  };
  @override
  Future<Map<String, dynamic>> submit(String conversationId, Map<String, dynamic> submission) async {
    submissions++;
    if (fail) throw StateError('connection interrupted');
    final result = <String, dynamic>{
      ...submission, 'status': 'completed',
      'result': {'ok': true, 'message_id': 'saved-follow-up'},
    };
    records.add(result);
    return result;
  }
}

Widget _wrap(Widget child, {Locale? locale}) {
  final readAloud = _ReadAloud();
  when(() => readAloud.messageId).thenReturn(null);
  when(() => readAloud.active).thenReturn(false);
  when(() => readAloud.state).thenReturn(ListeningState.idle);
  return ChangeNotifierProvider<ReadAloudController>.value(
    value: readAloud,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

ChatMessage _message(List<Map<String, dynamic>> components, {bool nested = false}) {
  final result = {
    'tool_call_id': 'call-1', 'tool_name': 'render_ui',
    'result': {'ok': true, 'presentation': {
      'summary': 'A useful visual answer', 'surface_id': 'example',
      'components': components,
      'actions': [{'id': 'choose', 'kind': 'follow_up', 'prompt': 'Explain this choice'}],
    }},
  };
  return ChatMessage(id: 'message-1', role: 'tool_result', content: 'A useful visual answer',
    createdAt: DateTime(2026), metadata: nested ? {'tool_result': result} : result);
}

void main() {
  setUp(() => rootBundle.evict('backend/app/schemas/visual_ui_catalog.json'));
  testWidgets('structured catalog adapts to width and enlarged text', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final message = _message([
      {'id': 'root', 'component': 'Column', 'children': ['compare', 'note', 'facts', 'progress', 'details']},
      {'id': 'compare', 'component': 'Comparison', 'items': [
        {'title': 'Portable option', 'badge': 'Recommended', 'highlighted': true,
          'attributes': [{'label': 'Best for', 'value': 'A compact setup with a long description that should wrap without clipping.'}]},
        {'title': 'Desktop option', 'attributes': [{'label': 'Best for', 'value': 'A dedicated workspace'}]},
      ]},
      {'id': 'note', 'component': 'Callout', 'title': 'Recommendation', 'text': 'Choose based on the space available.', 'tone': 'info'},
      {'id': 'facts', 'component': 'KeyValue', 'items': [{'label': 'Available colors', 'value': 'Blue and green'}]},
      {'id': 'progress', 'component': 'Progress', 'label': 'Setup progress', 'value': 75, 'detail': 'Three of four tasks complete'},
      {'id': 'details', 'component': 'Accordion', 'items': [{'title': 'Why this choice?', 'text': 'Supporting explanation'}]},
    ]);
    for (final width in [320.0, 768.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(_wrap(MediaQuery(
          data: MediaQueryData(size: Size(width, 2400), textScaler: TextScaler.linear(scale)),
          child: VisualAnswer(key: ValueKey('$width-$scale'), message: message, conversationId: null, canSubmit: false),
        )));
        await tester.pumpAndSettle();
        expect(find.text('Available colors'), findsOneWidget);
        expect(find.text('75%'), findsOneWidget);
        expect(find.text('Supporting explanation'), findsNothing);
        final portable = tester.getTopLeft(find.text('Portable option'));
        final desktop = tester.getTopLeft(find.text('Desktop option'));
        if (width < 480 * scale + 12) {
          expect(desktop.dy, greaterThan(portable.dy));
        } else {
          expect(desktop.dx, greaterThan(portable.dx));
        }
        expect(tester.takeException(), isNull, reason: 'width=$width scale=$scale');
      }
    }
    await tester.ensureVisible(find.text('Why this choice?'));
    await tester.tap(find.text('Why this choice?'));
    await tester.pumpAndSettle();
    expect(find.text('Supporting explanation'), findsOneWidget);
  });

  testWidgets('mobile tables preserve labels and paginate filtered rows', (tester) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(VisualTable(data: {
      'columns': ['Name', 'Details'],
      'rows': List.generate(12, (i) => ['Option $i', 'A long readable description for option $i. ' * 4]),
    })));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Name'), findsNWidgets(10));
    expect(find.text('Option 10'), findsNothing);
    await tester.ensureVisible(find.text('Show more rows'));
    await tester.tap(find.text('Show more rows'));
    await tester.pumpAndSettle();
    expect(find.text('Option 10'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'no matching option');
    await tester.pumpAndSettle();
    expect(find.text('No matching rows'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive form preserves edits when columns change', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final submitted = <Map<String, dynamic>>[];
    final form = VisualForm(data: {
      'fields': [
        {'name': 'name', 'label': 'Name', 'type': 'text'},
        {'name': 'count', 'label': 'Count', 'type': 'number'},
      ],
      'action': 'save', 'submitLabel': 'Save details',
    }, status: null, enabled: true, busy: false, onSubmit: (v) async => submitted.add(v));
    tester.view.physicalSize = const Size(900, 1000);
    await tester.pumpWidget(_wrap(form));
    await tester.enterText(find.byType(TextFormField).first, 'My choice');
    final desktopFields = tester.widgetList<SizedBox>(find.descendant(of: find.byType(VisualGrid), matching: find.byType(SizedBox)));
    expect(desktopFields.first.width, lessThan(500));
    tester.view.physicalSize = const Size(320, 1000);
    await tester.pumpAndSettle();
    expect(find.text('My choice'), findsOneWidget);
    await tester.tap(find.text('Save details'));
    expect(submitted.single['name'], 'My choice');
    expect(tester.takeException(), isNull);
  });

  testWidgets('pie charts keep long labels in a wrapping legend', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(const VisualChart(data: {
      'kind': 'pie', 'labels': ['An unusually long category description', 'Another category'],
      'series': [{'label': 'Distribution', 'values': [70, 30]}],
    })));
    await tester.pumpAndSettle();
    expect(find.text('An unusually long category description: 70'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('declared tool failures display their explanation', (tester) async {
    await tester.pumpWidget(_wrap(VisualForm(
      data: {'fields': [], 'action': 'save', 'submitLabel': 'Save'},
      status: {'status': 'failed', 'result': {'ok': false, 'content': 'Calendar rejected this request'}},
      enabled: false, busy: false, onSubmit: (_) async {},
    )));
    expect(find.textContaining('Calendar rejected this request'), findsOneWidget);
  });
  testWidgets('malformed select shows an error instead of crashing', (tester) async {
    await tester.pumpWidget(_wrap(VisualForm(
      data: {'fields': [{'name': 'choice', 'label': 'Choice', 'type': 'select',
        'options': ['A'], 'value': 7}], 'action': 'choose', 'submitLabel': 'Submit'},
      status: null, enabled: true, busy: false, onSubmit: (_) async {},
    )));
    await tester.pumpAndSettle();
    expect(find.text('Could not display or update this visual answer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('GenUI composes cards at mobile and desktop widths', (tester) async {
    final message = _message([
      {'id': 'root', 'component': 'Row', 'children': ['a', 'b']},
      {'id': 'a', 'component': 'Metric', 'label': 'Sales', 'value': '42'},
      {'id': 'b', 'component': 'Card', 'title': 'Plan', 'children': ['text']},
      {'id': 'text', 'component': 'Text', 'text': 'Start small'},
    ], nested: true);
    for (final width in [360.0, 1100.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_wrap(VisualAnswer(
        key: ValueKey(width), message: message, conversationId: null, canSubmit: false,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Start small'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('choices submit once and restore completed state', (tester) async {
    final service = _Service();
    final message = _message([{
      'id': 'root', 'component': 'Choices', 'action': 'choose',
      'options': [{'label': 'Option A', 'value': 'A'}, {'label': 'Option B', 'value': 'B'}],
    }]);
    Widget answer(Key key) => _wrap(VisualAnswer(
      key: key, message: message, conversationId: 'chat-1', canSubmit: true,
      service: service,
    ));
    await tester.pumpWidget(answer(const ValueKey('first')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option A'));
    await tester.pumpAndSettle();
    expect(service.submissions, 1);
    expect(find.text('Completed'), findsOneWidget);
    await tester.tap(find.text('Option A'));
    await tester.pumpAndSettle();
    expect(service.submissions, 1);
    await tester.pumpWidget(answer(const ValueKey('reopened')));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(service.submissions, 1);
  });

  testWidgets('interrupted submission is visible and cannot auto retry', (tester) async {
    final service = _Service()..fail = true;
    await tester.pumpWidget(_wrap(VisualAnswer(
      message: _message([{'id': 'root', 'component': 'Choices', 'action': 'choose',
        'options': [{'label': 'Choose', 'value': 'A'}]}]),
      conversationId: 'chat-1', canSubmit: true, service: service,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.textContaining('connection interrupted'), findsOneWidget);
    expect(service.submissions, 1);
    expect(find.text('Check submission status'), findsOneWidget);
  });

  testWidgets('tables filter and sort numbers locally', (tester) async {
    await tester.pumpWidget(_wrap(const VisualTable(data: {
      'columns': ['Name', 'Count'], 'rows': [['Ten', 10], ['Two', 2]],
    })));
    await tester.tap(find.text('Count'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Two')).dy, lessThan(tester.getTopLeft(find.text('Ten')).dy));
    await tester.enterText(find.byType(TextField), 'Ten');
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsNothing);
    expect(find.descendant(of: find.byType(DataTable), matching: find.text('Ten')), findsOneWidget);
  });

  testWidgets('charts render and allow hiding a series', (tester) async {
    await tester.pumpWidget(_wrap(const VisualChart(data: {
      'kind': 'line', 'labels': ['Jan', 'Feb'],
      'series': [{'label': 'Sales', 'values': [10, 20]}, {'label': 'Costs', 'values': [5, 6]}],
    })));
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);
    await tester.tap(find.text('Costs'));
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('required form validates before applying without another confirmation', (tester) async {
    final submitted = <Map<String, dynamic>>[];
    await tester.pumpWidget(_wrap(VisualForm(
      data: {'fields': [{'name': 'name', 'label': 'Reminder', 'type': 'text', 'required': true}],
        'action': 'save', 'submitLabel': 'Create reminder'},
      status: null, enabled: true, busy: false, onSubmit: (v) async => submitted.add(v),
    ), locale: const Locale('es')));
    await tester.tap(find.text('Create reminder'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.text('Este campo es obligatorio'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Water plants');
    await tester.tap(find.text('Create reminder'));
    expect(submitted.single['name'], 'Water plants');
  });
}
