import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/mentions/models/mention_candidate.dart';
import 'package:garbanzo_ai/features/mentions/widgets/mention_autocomplete.dart';
import 'package:garbanzo_ai/features/mentions/widgets/mention_text_controller.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

const _people = [
  MentionCandidate(
    kind: MentionKind.member,
    id: 'ana@example.com',
    label: 'Ana',
    sublabel: 'ana@example.com',
    insertText: '@Ana',
  ),
  MentionCandidate(
    kind: MentionKind.member,
    id: 'bob@example.com',
    label: 'Bob',
    insertText: '@Bob',
  ),
  MentionCandidate(
    kind: MentionKind.agent,
    id: 'agent-1',
    label: 'Scribe',
    sublabel: 'llama3',
    insertText: '@Scribe',
  ),
];

const _tools = [
  MentionCandidate(
    kind: MentionKind.tool,
    id: 'srv:web_search',
    label: 'web_search',
    insertText: '#web_search',
  ),
];

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  MentionCandidate? inserted;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    inserted = null;
  });

  tearDown(() {
    controller.dispose();
    focusNode.dispose();
  });

  Widget app() => MaterialApp(
    
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: MentionAutocomplete(
          controller: controller,
          focusNode: focusNode,
          sources: {'@': () => _people, '#': () => _tools},
          onMentionInserted: (c) => inserted = c,
          child: TextField(controller: controller, focusNode: focusNode),
        ),
      ),
    ),
  );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  Finder panel() => find.byKey(const Key('mention_suggestions'));

  testWidgets('typing a trigger opens the panel with all candidates', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, 'hello @');

    expect(panel(), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Scribe'), findsOneWidget);
  });

  testWidgets('the query filters candidates and no match closes the panel', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, '@scr');
    expect(find.text('Scribe'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);

    await type(tester, '@zzz');
    expect(panel(), findsNothing);
  });

  testWidgets('mid-word triggers never open the panel', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, 'mail@ex');
    expect(panel(), findsNothing);
  });

  testWidgets('tapping a suggestion inserts it and keeps typing possible', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, 'hey @a');
    await tester.tap(find.text('Ana'));
    await tester.pump();

    expect(controller.text, 'hey @Ana ');
    expect(controller.selection.baseOffset, 9);
    expect(panel(), findsNothing);
    expect(inserted?.id, 'ana@example.com');
  });

  testWidgets('arrow keys move the highlight and Enter inserts', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, '@');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '@Bob ');
    expect(panel(), findsNothing);
  });

  testWidgets('arrow up wraps to the last candidate', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, '@');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(controller.text, '@Scribe ');
  });

  testWidgets('Escape closes the panel without inserting', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, '@');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(panel(), findsNothing);
    expect(controller.text, '@');
  });

  testWidgets('different triggers use their own sources', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, 'run #');
    expect(find.text('web_search'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
  });

  testWidgets('losing focus closes the panel', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await type(tester, '@');
    expect(panel(), findsOneWidget);

    focusNode.unfocus();
    await tester.pump();
    expect(panel(), findsNothing);
  });

  group('MentionTextController', () {
    testWidgets('styles mention tokens with the primary color', (tester) async {
      final mentionController = MentionTextController(
        text: 'hi @Ana and mail@x.com',
      );
      addTearDown(mentionController.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      final span = mentionController.buildTextSpan(
        context: ctx,
        withComposing: false,
      );

      final children = span.children!.cast<TextSpan>();
      expect(children.map((s) => s.text), ['hi ', '@Ana', ' and mail@x.com']);
      expect(children[1].style?.color, Theme.of(ctx).colorScheme.primary);
      expect(children[0].style?.color, isNull);
    });
  });
}
