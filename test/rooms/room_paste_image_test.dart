import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/services/clipboard_image_reader.dart';
import 'package:garbanzo_ai/features/chat/widgets/input/attachment_preview.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';
import 'package:garbanzo_ai/features/rooms/widgets/room_chat_view.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

import 'fake_room_channel.dart';

class _MockRoomService extends Mock implements RoomService {}

final _now = DateTime.utc(2026, 9, 15);

Room _room() => Room(
  id: 'r1',
  name: 'Room One',
  ownerId: 'owner@x.com',
  isPublic: false,
  maxAgentTurnDepth: 3,
  mode: 'chat',
  createdAt: _now,
  updatedAt: _now,
  memberCount: 1,
  agentCount: 0,
  members: [
    RoomMember(
      roomId: 'r1',
      userId: 'owner@x.com',
      role: 'owner',
      joinedAt: _now,
    ),
  ],
);

/// A room view wired to a provider backed by a fake socket, so a sent message
/// can be inspected as the exact frame the backend would receive.
({RoomProvider provider, FakeRoomChannel channel}) _wireRoom() {
  final service = _MockRoomService();
  when(() => service.getRoom(any())).thenAnswer((_) async => _room());
  when(
    () => service.listMessages(any()),
  ).thenAnswer((_) async => const <RoomMessage>[]);

  final channel = FakeRoomChannel();
  final provider = RoomProvider(
    service: service,
    socketFactory: (id) => RoomSocketService(
      id,
      channelFactory: (_) => channel,
      tokenProvider: () async => 'test-token',
      uriBuilder: (_) => Uri.parse('ws://test/$id'),
    ),
  );
  return (provider: provider, channel: channel);
}

Widget _app(RoomProvider provider) =>
    ChangeNotifierProvider<RoomProvider>.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RoomChatView(roomId: 'r1', onOpenSettings: () {})),
      ),
    );

Future<void> _pressPaste(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  tearDown(() => ClipboardImageReader.debugOverride = null);

  testWidgets('a pasted image is staged in the room composer and sent with '
      'the message', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    ClipboardImageReader.debugOverride = () async => [
      (name: 'pasted_20260915_120000.png', bytes: bytes),
    ];

    final wired = _wireRoom();
    addTearDown(wired.provider.dispose);
    // Open the room up front so the composer is enabled when it mounts.
    await wired.provider.openRoom('r1');

    await tester.pumpWidget(_app(wired.provider));
    await tester.pump();

    // Nothing staged yet, so no preview bar and no way to send.
    expect(find.byType(AttachmentPreviewBar), findsNothing);
    expect(find.byKey(const ValueKey('send_button')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();
    await _pressPaste(tester);
    await tester.pump();

    // The pasted image is staged: a preview chip shows above the field and the
    // send button becomes available even though the message text is empty.
    expect(find.byType(AttachmentPreviewBar), findsOneWidget);
    expect(find.byType(AttachmentChip), findsOneWidget);
    final sendButton = find.byKey(const ValueKey('send_button'));
    expect(sendButton, findsOneWidget);

    await tester.tap(sendButton);
    await tester.pump();

    // The staged attachment travelled to the backend in the socket frame.
    expect(wired.channel.sent, hasLength(1));
    final frame = jsonDecode(wired.channel.sent.single) as Map<String, dynamic>;
    expect(frame['type'], 'post');
    final attachments = frame['attachments'] as List;
    expect(attachments, hasLength(1));
    final attachment = attachments.single as Map<String, dynamic>;
    expect(attachment['name'], 'pasted_20260915_120000.png');
    expect(attachment['mime_type'], 'image/png');
    expect(attachment['type'], 'image');
    expect(attachment['encoding'], 'base64');
    expect(attachment['data'], base64Encode(bytes));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pasting text in a room still reaches the message field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    ClipboardImageReader.debugOverride = () async => const [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'pasted text'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final wired = _wireRoom();
    addTearDown(wired.provider.dispose);
    await wired.provider.openRoom('r1');

    await tester.pumpWidget(_app(wired.provider));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('message_input')));
    await tester.pump();
    await _pressPaste(tester);
    await tester.pump();

    expect(tester.widget<TextField>(find.byKey(const ValueKey('message_input'))).controller!.text,
        'pasted text');
    expect(find.byType(AttachmentPreviewBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
