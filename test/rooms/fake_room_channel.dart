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
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  int? get closeCode => _closeCode;
}
