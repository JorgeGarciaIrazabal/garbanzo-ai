import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/friends/models/friend_models.dart';
import 'package:garbanzo_ai/features/friends/widgets/friend_picker_field.dart';

const _friends = [
  Friend(email: 'ana@example.com', friendshipId: 'f1', fullName: 'Ana Lopez'),
  Friend(email: 'bob@example.com', friendshipId: 'f2'),
];

void main() {
  late GlobalKey<FriendPickerFieldState> key;
  late List<String> lastSelection;

  Widget app({
    List<Friend> friends = _friends,
    Set<String> excludeEmails = const {},
  }) {
    key = GlobalKey<FriendPickerFieldState>();
    lastSelection = [];
    return MaterialApp(
      home: Scaffold(
        body: FriendPickerField(
          key: key,
          friends: friends,
          excludeEmails: excludeEmails,
          onChanged: (emails) => lastSelection = emails,
        ),
      ),
    );
  }

  testWidgets('suggests all friends and adds one as a chip on tap', (
    tester,
  ) async {
    await tester.pumpWidget(app());

    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('bob@example.com'), findsOneWidget);

    await tester.tap(find.text('Ana Lopez'));
    await tester.pump();

    expect(lastSelection, ['ana@example.com']);
    expect(key.currentState!.selectedEmails, ['ana@example.com']);
    // Selected friend leaves the suggestions.
    expect(find.byType(ActionChip), findsOneWidget);
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('typing filters suggestions by name and email', (tester) async {
    await tester.pumpWidget(app());

    await tester.enterText(
      find.byKey(const Key('friend_picker_input')),
      'lopez',
    );
    await tester.pump();

    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('bob@example.com'), findsNothing);
  });

  testWidgets('submitting free text adds raw emails (by-email fallback)', (
    tester,
  ) async {
    await tester.pumpWidget(app(friends: []));

    await tester.enterText(
      find.byKey(const Key('friend_picker_input')),
      'x@y.com, not-an-email, z@y.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(lastSelection, ['x@y.com', 'z@y.com']);
  });

  testWidgets('commitPendingText folds unsubmitted input into the selection', (
    tester,
  ) async {
    await tester.pumpWidget(app(friends: []));

    await tester.enterText(
      find.byKey(const Key('friend_picker_input')),
      'typed@example.com',
    );
    key.currentState!.commitPendingText();
    await tester.pump();

    expect(key.currentState!.selectedEmails, ['typed@example.com']);
  });

  testWidgets('deleting a chip removes it from the selection', (tester) async {
    await tester.pumpWidget(app());

    await tester.tap(find.text('Ana Lopez'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete')); // InputChip delete button
    await tester.pump();

    expect(lastSelection, isEmpty);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('excluded emails never appear as suggestions', (tester) async {
    await tester.pumpWidget(app(excludeEmails: {'bob@example.com'}));

    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('bob@example.com'), findsNothing);
  });

  testWidgets('duplicate adds are ignored', (tester) async {
    await tester.pumpWidget(app(friends: []));

    await tester.enterText(
      find.byKey(const Key('friend_picker_input')),
      'x@y.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('friend_picker_input')),
      'X@Y.com',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(key.currentState!.selectedEmails, ['x@y.com']);
  });
}
