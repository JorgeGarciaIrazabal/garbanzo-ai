import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';

import 'fake_room_channel.dart';

class _MockRoomService extends Mock implements RoomService {}

final _now = DateTime.utc(2026, 7, 11);

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
      agentCount: 1,
      members: [
        RoomMember(
          roomId: 'r1',
          userId: 'owner@x.com',
          role: 'owner',
          joinedAt: _now,
        ),
      ],
      agents: const [],
    );

/// Wires a provider to a mocked REST service and a single injected fake
/// channel. Returns both so the test can drive frames and inspect state.
({RoomProvider provider, _MockRoomService service}) _wire(
  FakeRoomChannel channel, {
  Duration typingExpiry = const Duration(seconds: 5),
  List<RoomMessage> Function()? messages,
}) {
  final service = _MockRoomService();
  when(() => service.getRoom(any())).thenAnswer((_) async => _room());
  when(() => service.listMessages(any()))
      .thenAnswer((_) async => messages?.call() ?? const <RoomMessage>[]);

  final provider = RoomProvider(
    service: service,
    typingExpiry: typingExpiry,
    socketFactory: (id) => RoomSocketService(
      id,
      channelFactory: (_) => channel,
      tokenProvider: () async => 'test-token',
      uriBuilder: (_) => Uri.parse('ws://test/$id'),
    ),
  );
  return (provider: provider, service: service);
}

void main() {
  group('RoomProvider streaming channel', () {
    test('stream_start adds an empty placeholder and claims the live channel',
        () async {
      final channel = FakeRoomChannel();
      final wired = _wire(channel);
      final provider = wired.provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.connectionState, RoomConnectionState.connected);

      channel.emit(jsonEncode({
        'type': 'stream_start',
        'message_id': 'm1',
        'agent_id': 'a1',
        'agent_name': 'Botty',
      }));
      await Future<void>.delayed(Duration.zero);

      expect(provider.streamingMessageId, 'm1');
      expect(provider.messages.where((m) => m.id == 'm1'), hasLength(1));
      expect(provider.messages.last.content, isEmpty);

      provider.dispose();
    });

    test('chunks accumulate through the throttled notifier, not the list',
        () async {
      final channel = FakeRoomChannel();
      final provider = _wire(channel).provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      channel.emit(jsonEncode({
        'type': 'stream_start',
        'message_id': 'm1',
        'agent_id': 'a1',
        'agent_name': 'Botty',
      }));
      await Future<void>.delayed(Duration.zero);

      var pushes = 0;
      provider.streamingMessage.addListener(() => pushes++);

      // 20 chunks back-to-back — far faster than the 80ms push interval.
      for (var i = 0; i < 20; i++) {
        channel.emit(jsonEncode({
          'type': 'chunk',
          'message_id': 'm1',
          'content': 'x',
        }));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Coalesced into a handful of pushes, but nothing was dropped.
      expect(pushes, lessThan(20));
      expect(provider.streamingMessage.value?.content, 'x' * 20);
      // The list copy still holds the empty placeholder — the live content
      // lives on the notifier until a structural event syncs it.
      expect(
        provider.messages.firstWhere((m) => m.id == 'm1').content,
        isEmpty,
      );

      provider.dispose();
    });

    test('thinking chunks accumulate into meta (incl. legacy alias)', () async {
      final channel = FakeRoomChannel();
      final provider = _wire(channel).provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      channel.emit(jsonEncode({
        'type': 'stream_start',
        'message_id': 'm1',
        'agent_id': 'a1',
      }));
      await Future<void>.delayed(Duration.zero);

      channel.emit(jsonEncode({
        'type': 'thinking',
        'message_id': 'm1',
        'content': 'hmm ',
      }));
      // Legacy pre-unification name still handled.
      channel.emit(jsonEncode({
        'type': 'thinking_chunk',
        'message_id': 'm1',
        'content': 'ok',
      }));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(provider.streamingMessage.value?.meta?['thinking'], 'hmm ok');

      provider.dispose();
    });

    test('the canonical message finalizes and releases the live channel',
        () async {
      final channel = FakeRoomChannel();
      final provider = _wire(channel).provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      channel.emit(jsonEncode({
        'type': 'stream_start',
        'message_id': 'm1',
        'agent_id': 'a1',
      }));
      channel.emit(jsonEncode({
        'type': 'chunk',
        'message_id': 'm1',
        'content': 'hello',
      }));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(provider.streamingMessageId, 'm1');

      channel.emit(jsonEncode({
        'type': 'message',
        'message': {
          'id': 'm1',
          'room_id': 'r1',
          'role': 'assistant',
          'sender_agent_id': 'a1',
          'content': 'hello',
          'created_at': _now.toIso8601String(),
        },
      }));
      await Future<void>.delayed(Duration.zero);

      expect(provider.streamingMessageId, isNull);
      expect(provider.streamingMessage.value, isNull);
      expect(
        provider.messages.firstWhere((m) => m.id == 'm1').content,
        'hello',
      );

      provider.dispose();
    });
  });

  group('RoomProvider reconnect', () {
    test('refetches messages after a reconnect fills the gap', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _MockRoomService();
        when(() => service.getRoom(any())).thenAnswer((_) async => _room());
        var listCalls = 0;
        when(() => service.listMessages(any())).thenAnswer((_) async {
          listCalls++;
          return const <RoomMessage>[];
        });

        final provider = RoomProvider(
          service: service,
          socketFactory: (id) => RoomSocketService(
            id,
            channelFactory: (_) {
              final c = FakeRoomChannel();
              channels.add(c);
              return c;
            },
            tokenProvider: () async => 'test-token',
            uriBuilder: (_) => Uri.parse('ws://test/$id'),
          ),
        );

        provider.openRoom('r1');
        async.flushMicrotasks();
        expect(provider.connectionState, RoomConnectionState.connected);
        expect(listCalls, 1, reason: 'initial load on open');

        // Drop the socket; the backoff reconnect brings it back.
        channels[0].serverClose();
        async.flushMicrotasks();
        expect(provider.connectionState, RoomConnectionState.reconnecting);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(provider.connectionState, RoomConnectionState.connected);
        expect(listCalls, 2, reason: 'messages refetched after reconnect');
      });
    });
  });

  group('RoomProvider typing', () {
    test('inbound typing appears then auto-expires', () async {
      final channel = FakeRoomChannel();
      final provider = _wire(
        channel,
        typingExpiry: const Duration(milliseconds: 120),
      ).provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      channel.emit(jsonEncode({
        'type': 'typing',
        'user_id': 'alice@x.com',
        'typing': true,
      }));
      await Future<void>.delayed(Duration.zero);
      expect(provider.typingUsers, contains('alice@x.com'));

      // No refresh arrives → the entry expires on its own.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(provider.typingUsers, isEmpty);

      provider.dispose();
    });

    test('an explicit typing:false clears immediately', () async {
      final channel = FakeRoomChannel();
      final provider = _wire(channel).provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      channel.emit(jsonEncode(
          {'type': 'typing', 'user_id': 'bob@x.com', 'typing': true}));
      await Future<void>.delayed(Duration.zero);
      expect(provider.typingUsers, contains('bob@x.com'));

      channel.emit(jsonEncode(
          {'type': 'typing', 'user_id': 'bob@x.com', 'typing': false}));
      await Future<void>.delayed(Duration.zero);
      expect(provider.typingUsers, isEmpty);

      provider.dispose();
    });

    test('composer changes send typing:true once per interval, false on clear',
        () async {
      final channel = FakeRoomChannel();
      final provider = _wire(channel).provider;

      await provider.openRoom('r1');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bool isTyping(String frame, bool value) {
        final decoded = jsonDecode(frame) as Map<String, dynamic>;
        return decoded['type'] == 'typing' && decoded['typing'] == value;
      }

      provider.handleComposerChanged('h');
      provider.handleComposerChanged('he');
      provider.handleComposerChanged('hel');
      // Debounced: only one typing:true within the send interval.
      expect(channel.sent.where((f) => isTyping(f, true)), hasLength(1));

      provider.handleComposerChanged('');
      // Emptying the field flips it off.
      expect(channel.sent.where((f) => isTyping(f, false)), hasLength(1));

      provider.dispose();
    });
  });
}
