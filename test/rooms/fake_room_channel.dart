import 'dart:async';

import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';

/// In-memory [RoomChannel] for driving the socket service in tests without a
/// real WebSocket.
class FakeRoomChannel implements RoomChannel {
  FakeRoomChannel({bool readyNow = true}) {
    if (readyNow) _ready.complete();
  }

  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final Completer<void> _ready = Completer<void>();

  /// Frames the service asked us to send, in order.
  final List<String> sent = [];
  bool closed = false;
  int? _closeCode;

  /// The close code the service passed to [close], if any. Kept separate from
  /// [_closeCode] (which fakes a server-initiated close) so a test can assert
  /// what *we* sent.
  int? sentCloseCode;

  /// Complete the handshake future (for channels created with readyNow: false).
  void completeReady() {
    if (!_ready.isCompleted) _ready.complete();
  }

  /// Fail the handshake future.
  void failReady(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
  }

  /// Deliver an inbound frame to the service.
  void emit(String frame) {
    if (!_incoming.isClosed) _incoming.add(frame);
  }

  /// Simulate a transport error, which mobile sockets may emit before done.
  void serverError(Object error) {
    if (!_incoming.isClosed) _incoming.addError(error);
  }

  /// Simulate the server closing the socket (optionally with a close code).
  void serverClose({int? code}) {
    _closeCode = code;
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close([int? code, String? reason]) async {
    // Mirror the real transport: `web_socket`'s checkCloseCode rejects anything
    // other than 1000 or 3000-4999. Without this the fake would accept codes
    // that throw in production, and the bug would only ever show up on a phone.
    if (code != null && code != 1000 && !(code >= 3000 && code <= 4999)) {
      throw ArgumentError(
        'Invalid argument: $code, close code must be 1000 or in the range '
        '3000-4999',
      );
    }
    closed = true;
    sentCloseCode = code;
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  int? get closeCode => _closeCode;
}
