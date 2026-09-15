/// Widget tests for the sidebar thread/room actions menu.
///
/// The menu is the single place pin, download, and delete live: one trailing
/// overflow button instead of a row of icons.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/conversation_list_widget.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

Conversation _conversation({String id = 'c1', bool pinned = false}) =>
    Conversation(
      id: id,
      title: 'Convo One',
      model: 'llama3.2',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      isPinned: pinned,
    );

Room _room({String id = 'r1'}) => Room(
  id: id,
  name: 'Room One',
  ownerId: 'test@example.com',
  isPublic: false,
  maxAgentTurnDepth: 3,
  mode: 'chat',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  memberCount: 1,
  agentCount: 0,
);

Widget _threadsHost(
  List<Conversation> conversations, {
  void Function(String)? onDelete,
  void Function(Conversation)? onDownload,
  void Function(String)? onTogglePin,
}) => ChangeNotifierProvider<SearchProvider>(
  create: (_) => SearchProvider(),
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ConversationListWidget(
        conversations: conversations,
        selectedId: null,
        onSelect: (_) {},
        onDelete: onDelete ?? (_) {},
        onNewChat: () {},
        onTogglePin: onTogglePin,
        onDownload: onDownload,
        embedded: true,
      ),
    ),
  ),
);

Widget _roomsHost(
  List<Room> rooms, {
  void Function(Room)? onDelete,
  void Function(Room)? onDownload,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: RoomsListView(
      rooms: rooms,
      onSelect: (_) {},
      onDelete: onDelete ?? (_) {},
      onDownload: onDownload,
    ),
  ),
);

/// Opens the row's overflow menu.
Future<void> _openMenu(WidgetTester tester, Finder menu) async {
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

void main() {
  group('thread actions menu', () {
    testWidgets('combines pin, download and delete, and nothing else', (
      tester,
    ) async {
      await tester.pumpWidget(
        _threadsHost(
          [_conversation()],
          onTogglePin: (_) {},
          onDownload: (_) {},
        ),
      );

      // The old always-visible trailing icons are gone.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);

      await _openMenu(
        tester,
        find.byKey(const ValueKey('conversation_actions_menu')),
      );

      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Download transcript'), findsOneWidget);
      expect(find.text('Delete conversation'), findsOneWidget);
    });

    testWidgets('a pinned thread offers Unpin', (tester) async {
      await tester.pumpWidget(
        _threadsHost([_conversation(pinned: true)], onTogglePin: (_) {}),
      );
      await _openMenu(
        tester,
        find.byKey(const ValueKey('conversation_actions_menu')),
      );

      expect(find.text('Unpin'), findsOneWidget);
      expect(find.text('Pin'), findsNothing);
    });

    testWidgets('each item calls back with its conversation', (tester) async {
      final deleted = <String>[];
      final downloaded = <String>[];
      final pinned = <String>[];
      await tester.pumpWidget(
        _threadsHost(
          [_conversation()],
          onDelete: deleted.add,
          onDownload: (c) => downloaded.add(c.id),
          onTogglePin: pinned.add,
        ),
      );

      await _openMenu(
        tester,
        find.byKey(const ValueKey('conversation_actions_menu')),
      );
      await tester.tap(find.text('Download transcript'));
      await tester.pumpAndSettle();

      await _openMenu(
        tester,
        find.byKey(const ValueKey('conversation_actions_menu')),
      );
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      await _openMenu(
        tester,
        find.byKey(const ValueKey('conversation_actions_menu')),
      );
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();

      // Delete is destructive, so the menu only opens the confirmation.
      expect(deleted, isEmpty);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(downloaded, ['c1']);
      expect(pinned, ['c1']);
      expect(deleted, ['c1']);
    });

    testWidgets('without a download handler the item is not offered', (
      tester,
    ) async {
      await tester.pumpWidget(_threadsHost([_conversation()]));
      await _openMenu(
        tester,
        find.byKey(const ValueKey('conversation_actions_menu')),
      );

      expect(find.text('Download transcript'), findsNothing);
      expect(find.text('Delete conversation'), findsOneWidget);
    });
  });

  group('room actions menu', () {
    testWidgets('offers download and delete', (tester) async {
      await tester.pumpWidget(_roomsHost([_room()], onDownload: (_) {}));

      await _openMenu(tester, find.byKey(const ValueKey('room_actions_menu')));

      expect(find.text('Download transcript'), findsOneWidget);
      expect(find.text('Delete room'), findsOneWidget);
    });

    testWidgets('each item calls back with its room', (tester) async {
      final downloaded = <String>[];
      final deleted = <String>[];
      await tester.pumpWidget(
        _roomsHost(
          [_room()],
          onDownload: (r) => downloaded.add(r.id),
          onDelete: (r) => deleted.add(r.id),
        ),
      );

      await _openMenu(tester, find.byKey(const ValueKey('room_actions_menu')));
      await tester.tap(find.text('Download transcript'));
      await tester.pumpAndSettle();

      await _openMenu(tester, find.byKey(const ValueKey('room_actions_menu')));
      await tester.tap(find.text('Delete room'));
      await tester.pumpAndSettle();

      expect(deleted, isEmpty);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(downloaded, ['r1']);
      expect(deleted, ['r1']);
    });
  });
}
