import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/log.dart';

/// Lifecycle of a room's live socket, surfaced to the UI so it can show a
/// "reconnecting…" banner and a retry affordance.
enum RoomConnectionState {
  /// First connection attempt in flight (no prior successful connection).
  connecting,

  /// Live: frames flow in both directions.
  connected,

  /// Dropped unexpectedly; a backoff reconnect is scheduled.
  reconnecting,

  /// Reconnect attempts exhausted — waiting for a manual retry.
  failed,

  /// Closed on purpose (leave room) or refused by the server (auth).
  closed,
}

/// Minimal duplex transport the socket service needs. Wrapping the concrete
/// [WebSocketChannel] behind this interface lets tests inject an in-memory
/// fake without a real network socket.
abstract class RoomChannel {
  Stream<dynamic> get stream;

  /// Completes once the underlying socket is connected; throws on failure.
  Future<void> get ready;

  void send(String data);

  Future<void> close([int? code, String? reason]);

  /// The close code reported by the peer once [stream] is done, if any.
  int? get closeCode;
}

class _WsRoomChannel implements RoomChannel {
  _WsRoomChannel(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  void send(String data) => _channel.sink.add(data);

  @override
  Future<void> close([int? code, String? reason]) =>
      _channel.sink.close(code, reason);

  @override
  int? get closeCode => _channel.closeCode;
}

typedef RoomChannelFactory = RoomChannel Function(Uri uri);

/// WebSocket client for live room events, with automatic reconnect.
///
/// Events sent:
///   {type: 'post', content: '...'}
///   {type: 'typing', typing: bool}
///
/// Events received are forwarded verbatim as `Map<String, dynamic>` on
/// [events]. Callers can dispatch on `type`.
///
/// On an unexpected disconnect the service reconnects with exponential backoff
/// (1s, 2s, 4s, 8s… capped at 8s, up to [maxReconnectAttempts] tries). It does
/// NOT reconnect after an explicit [close] or when the server refuses the
/// socket with a policy-violation close code (auth failure) — retrying those
/// would just loop. [connectionState] exposes the current phase so the UI can
/// react.
class RoomSocketService {
  RoomSocketService(
    this.roomId, {
    RoomChannelFactory? channelFactory,
    Future<String?> Function()? tokenProvider,
    Uri Function(String token)? uriBuilder,
    this.maxReconnectAttempts = 6,
  }) : _channelFactory =
           channelFactory ??
           ((uri) => _WsRoomChannel(WebSocketChannel.connect(uri))),
       _tokenProvider = tokenProvider ?? (() => ApiClient.instance.getToken()),
       _uriBuilder =
           uriBuilder ??
           ((token) => ApiClient.instance.wsUri(
             '/api/v1/ws/rooms/$roomId',
             queryParameters: {'token': token},
           ));

  final String roomId;
  final int maxReconnectAttempts;

  final RoomChannelFactory _channelFactory;
  final Future<String?> Function() _tokenProvider;
  final Uri Function(String token) _uriBuilder;

  RoomChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  // Created eagerly so [events] is a stable, subscribable stream from the
  // moment the service exists (callers subscribe before [connect]).
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  Timer? _reconnectTimer;
  int _attempt = 0;
  bool _closed = false;

  /// True once we've had at least one successful connection, so a later
  /// `connected` transition can be recognised as a *re*connect (gap to fill).
  bool _hadConnection = false;

  /// The current transport phase. UI listens to this for banners.
  final ValueNotifier<RoomConnectionState> connectionState = ValueNotifier(
    RoomConnectionState.connecting,
  );

  Stream<Map<String, dynamic>> get events => _controller.stream;

  Future<void> connect() async {
    await _open();
  }

  Future<void> _open() async {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final String? token;
    try {
      token = await _tokenProvider();
    } catch (e) {
      logDebug('Room socket token fetch failed: $e');
      _scheduleReconnect();
      return;
    }
    if (_closed) return;
    if (token == null) {
      // No credentials → this is an auth problem, not a transient drop.
      _fail(closed: true);
      return;
    }

    connectionState.value = _hadConnection
        ? RoomConnectionState.reconnecting
        : RoomConnectionState.connecting;

    final RoomChannel channel;
    try {
      channel = _channelFactory(_uriBuilder(token));
    } catch (e) {
      logDebug('Room socket channel create failed: $e');
      _scheduleReconnect();
      return;
    }
    _channel = channel;

    // Await the handshake so we distinguish "connected" from "immediately
    // refused" before treating the socket as live.
    unawaited(
      channel.ready
          .then((_) {
            if (_closed || !identical(_channel, channel)) return;
            _onConnected();
          })
          .catchError((Object e) {
            if (_closed || !identical(_channel, channel)) return;
            logDebug('Room socket handshake failed: $e');
            _scheduleReconnect();
          }),
    );

    _channelSub = channel.stream.listen(
      (raw) {
        // A frame is proof the socket is live (covers transports whose `ready`
        // resolves eagerly).
        if (connectionState.value != RoomConnectionState.connected) {
          _onConnected();
        }
        try {
          final parsed = jsonDecode(raw as String) as Map<String, dynamic>;
          if (!_controller.isClosed) _controller.add(parsed);
        } catch (_) {
          // ignore malformed frames
        }
      },
      onError: (Object e) {
        // Surface the error to listeners, but let onDone drive reconnect so we
        // can inspect the close code.
        if (!_controller.isClosed) _controller.addError(e);
      },
      onDone: () => _handleDisconnect(channel.closeCode),
      cancelOnError: false,
    );
  }

  void _onConnected() {
    _attempt = 0;
    _hadConnection = true;
    if (connectionState.value != RoomConnectionState.connected) {
      connectionState.value = RoomConnectionState.connected;
    }
  }

  void _handleDisconnect(int? closeCode) {
    if (_closed) return;
    _channelSub?.cancel();
    _channelSub = null;
    // Policy-violation (1008) is how the backend refuses/kicks a socket
    // (bad/expired token, removed from room). Reconnecting would loop, so stop.
    if (closeCode == ws_status.policyViolation) {
      _fail(closed: true);
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _channel = null;
    if (_attempt >= maxReconnectAttempts) {
      _fail(closed: false);
      return;
    }
    // 1s, 2s, 4s, 8s, … capped at 8s.
    final seconds = 1 << _attempt;
    final delay = Duration(seconds: seconds > 8 ? 8 : seconds);
    _attempt++;
    connectionState.value = RoomConnectionState.reconnecting;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_open()));
  }

  void _fail({required bool closed}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (closed) _closed = true;
    connectionState.value = closed
        ? RoomConnectionState.closed
        : RoomConnectionState.failed;
  }

  /// Manual retry from the "failed" state (user tapped "Try again").
  Future<void> retry() async {
    if (_closed) return;
    _attempt = 0;
    await _open();
  }

  void post(String content) {
    _channel?.send(jsonEncode({'type': 'post', 'content': content}));
  }

  void typing(bool active) {
    _channel?.send(jsonEncode({'type': 'typing', 'typing': active}));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    connectionState.value = RoomConnectionState.closed;
    await _channelSub?.cancel();
    _channelSub = null;
    await _channel?.close();
    if (!_controller.isClosed) await _controller.close();
    _channel = null;
    // Note: [connectionState] is intentionally NOT disposed here — the owning
    // provider removes its listener and drops the reference; leaving the
    // notifier intact avoids any use-after-dispose if a late callback reads it.
  }
}
