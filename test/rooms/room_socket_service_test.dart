import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';

import 'fake_room_channel.dart';

/// Builds a socket service wired to a list of fake channels — one produced per
/// (re)connect attempt — with hermetic token/URI providers.
RoomSocketService _service(
  List<FakeRoomChannel> channels, {
  bool readyNow = true,
  int maxReconnectAttempts = 6,
}) {
  return RoomSocketService(
    'room-1',
    maxReconnectAttempts: maxReconnectAttempts,
    tokenProvider: () async => 'test-token',
    uriBuilder: (_) => Uri.parse('ws://test/room-1'),
    channelFactory: (_) {
      final channel = FakeRoomChannel(readyNow: readyNow);
      channels.add(channel);
      return channel;
    },
  );
}

void main() {
  group('RoomSocketService connection lifecycle', () {
    test('reports connected once the handshake completes', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels);

        service.connect();
        async.flushMicrotasks();

        expect(channels, hasLength(1));
        expect(service.connectionState.value, RoomConnectionState.connected);
      });
    });

    test('an unexpected close schedules a backoff reconnect and recovers', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels);

        service.connect();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.connected);

        // Server drops the socket with no close code (transient).
        channels[0].serverClose();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.reconnecting);
        expect(channels, hasLength(1)); // not yet — waiting out the backoff

        // First backoff is 1s.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(channels, hasLength(2));
        expect(service.connectionState.value, RoomConnectionState.connected);
      });
    });

    test('backoff grows 1s then 2s and gives up as failed after the cap', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        // Never completes the handshake, so each attempt just fails and the
        // attempt counter climbs to exhaustion. With maxReconnectAttempts: 2
        // the service schedules two reconnects (1s, then 2s) and fails on the
        // disconnect after the second one.
        final service =
            _service(channels, readyNow: false, maxReconnectAttempts: 2);

        service.connect();
        async.flushMicrotasks();
        expect(channels, hasLength(1));

        // Disconnect #1 → 1s backoff.
        channels[0].serverClose();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.reconnecting);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(channels, hasLength(2));

        // Disconnect #2 → 2s backoff (1s alone is not enough).
        channels[1].serverClose();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(channels, hasLength(2), reason: '2s backoff not elapsed yet');
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(channels, hasLength(3));

        // Disconnect #3 → attempts exhausted → failed, no further channel.
        channels[2].serverClose();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 8));
        async.flushMicrotasks();
        expect(channels, hasLength(3));
        expect(service.connectionState.value, RoomConnectionState.failed);
      });
    });

    test('a policy-violation close is treated as auth failure — no reconnect',
        () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels);

        service.connect();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.connected);

        channels[0].serverClose(code: ws_status.policyViolation);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(service.connectionState.value, RoomConnectionState.closed);
        expect(channels, hasLength(1)); // never retried
      });
    });

    test('retry() restarts from the failed state', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels, readyNow: false, maxReconnectAttempts: 1);

        service.connect();
        async.flushMicrotasks();
        channels[0].serverClose();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        // attempt 1 exhausted on the next drop.
        channels[1].serverClose();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.failed);

        // Manual retry opens a fresh channel; completing it connects.
        service.retry();
        async.flushMicrotasks();
        final fresh = channels.last;
        fresh.completeReady();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.connected);
      });
    });

    test('post serializes attachments in the backend AttachmentIn shape', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels);
        service.connect();
        async.flushMicrotasks();

        service.post(
          'look at these',
          attachments: [
            ChatAttachment(
              name: 'photo.png',
              mimeType: 'image/png',
              type: AttachmentType.image,
              bytes: Uint8List.fromList([1, 2, 3]),
            ),
            ChatAttachment(
              name: 'notes.txt',
              mimeType: 'text/plain',
              type: AttachmentType.document,
              bytes: Uint8List.fromList(utf8.encode('doc body')),
            ),
          ],
        );

        expect(channels[0].sent, hasLength(1));
        final frame = jsonDecode(channels[0].sent.single);
        expect(frame, {
          'type': 'post',
          'content': 'look at these',
          'attachments': [
            {
              'name': 'photo.png',
              'mime_type': 'image/png',
              'type': 'image',
              // Images travel base64-encoded…
              'data': base64Encode([1, 2, 3]),
            },
            {
              'name': 'notes.txt',
              'mime_type': 'text/plain',
              'type': 'document',
              // …documents travel as plain text.
              'data': 'doc body',
            },
          ],
        });
      });
    });

    test('post without attachments omits the attachments key entirely', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels);
        service.connect();
        async.flushMicrotasks();

        service.post('plain message');

        final frame =
            jsonDecode(channels[0].sent.single) as Map<String, dynamic>;
        expect(frame, {'type': 'post', 'content': 'plain message'});
        expect(frame.containsKey('attachments'), isFalse);
      });
    });

    test('close() cancels a pending reconnect timer', () {
      fakeAsync((async) {
        final channels = <FakeRoomChannel>[];
        final service = _service(channels);

        service.connect();
        async.flushMicrotasks();
        channels[0].serverClose();
        async.flushMicrotasks();
        expect(service.connectionState.value, RoomConnectionState.reconnecting);

        // Explicit close before the backoff fires must abort the reconnect.
        service.close();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(service.connectionState.value, RoomConnectionState.closed);
        expect(channels, hasLength(1)); // no reconnect happened
      });
    });
  });
}
