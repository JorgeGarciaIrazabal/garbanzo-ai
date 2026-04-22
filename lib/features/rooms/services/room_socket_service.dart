import 'dart:async';
import 'dart:convert';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client for live room events.
///
/// Events sent:
///   {type: 'post', content: '...'}
///   {type: 'typing', typing: bool}
///
/// Events received are forwarded verbatim as `Map<String, dynamic>` on
/// [events]. Callers can dispatch on `type`.
class RoomSocketService {
  RoomSocketService(this.roomId);

  final String roomId;

  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  bool _closed = false;

  Stream<Map<String, dynamic>> get events =>
      _controller?.stream ?? const Stream.empty();

  Future<void> connect() async {
    if (_channel != null) return;
    final token = await ApiClient.instance.getToken();
    if (token == null) {
      throw StateError('Cannot open WS without auth token');
    }
    final uri = ApiClient.instance.wsUri(
      '/api/v1/ws/rooms/$roomId',
      queryParameters: {'token': token},
    );
    _controller = StreamController<Map<String, dynamic>>.broadcast();
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(
      (raw) {
        try {
          final parsed = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller?.add(parsed);
        } catch (_) {
          // ignore malformed
        }
      },
      onError: (e) {
        _controller?.addError(e);
      },
      onDone: () {
        _controller?.close();
      },
    );
  }

  void post(String content) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(jsonEncode({'type': 'post', 'content': content}));
  }

  void typing(bool active) {
    _channel?.sink.add(jsonEncode({'type': 'typing', 'typing': active}));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel?.sink.close();
    await _controller?.close();
    _channel = null;
    _controller = null;
  }
}
