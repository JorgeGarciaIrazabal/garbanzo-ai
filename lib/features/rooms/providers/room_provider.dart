import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';

/// Tracks the user's list of rooms and the currently open room.
class RoomProvider extends ChangeNotifier {
  RoomProvider({
    RoomService? service,
    RoomSocketService Function(String roomId)? socketFactory,
    Duration typingExpiry = const Duration(seconds: 5),
    Duration typingSendInterval = const Duration(seconds: 3),
  }) : _service = service ?? RoomService.instance,
       _socketFactory = socketFactory ?? ((id) => RoomSocketService(id)),
       _typingExpiry = typingExpiry,
       _typingSendInterval = typingSendInterval;

  final RoomService _service;
  final RoomSocketService Function(String roomId) _socketFactory;
  final Duration _typingExpiry;
  final Duration _typingSendInterval;

  List<Room> _rooms = [];
  Room? _currentRoom;
  List<RoomMessage> _messages = [];
  List<String> _online = [];
  RoomSocketService? _socket;
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  bool _loading = false;
  String? _error;

  RoomConnectionState _connectionState = RoomConnectionState.closed;
  bool _wasConnected = false;

  /// In-progress agent streams keyed by message_id so chunks can accumulate.
  final Map<String, _StreamingMessage> _streaming = {};

  List<Room> get rooms => List.unmodifiable(_rooms);
  Room? get currentRoom => _currentRoom;
  List<RoomMessage> get messages => List.unmodifiable(_messages);
  List<String> get onlineUsers => List.unmodifiable(_online);
  bool get loading => _loading;
  String? get error => _error;
  RoomConnectionState get connectionState => _connectionState;

  // ==========================================================================
  // Streaming message channel
  // ==========================================================================
  //
  // Per-chunk agent content flows through this ValueNotifier instead of
  // notifyListeners(), so only the streaming bubble rebuilds — not the whole
  // room message list (which would also re-parse every visible message's
  // markdown on each token). The list itself only changes on structural
  // events: stream start, the canonical `message`, presence, typing,
  // connection-state changes, and errors.

  /// Live view of the agent message currently being streamed.
  final ValueNotifier<RoomMessage?> streamingMessage = ValueNotifier(null);

  /// ID of the in-flight agent placeholder currently owning the live channel.
  String? get streamingMessageId => _streamingMessageId;
  String? _streamingMessageId;

  static const _streamPushInterval = Duration(milliseconds: 80);
  DateTime _lastStreamPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamFlushTimer;
  RoomMessage? _pendingStreamMessage;

  void _pushStreamingUpdate(RoomMessage message, {bool force = false}) {
    _pendingStreamMessage = message;
    final now = DateTime.now();
    if (force || now.difference(_lastStreamPush) >= _streamPushInterval) {
      _streamFlushTimer?.cancel();
      _streamFlushTimer = null;
      _lastStreamPush = now;
      streamingMessage.value = message;
    } else {
      _streamFlushTimer ??= Timer(_streamPushInterval, () {
        _streamFlushTimer = null;
        _lastStreamPush = DateTime.now();
        final pending = _pendingStreamMessage;
        if (pending != null && pending.id == _streamingMessageId) {
          streamingMessage.value = pending;
        }
      });
    }
  }

  /// Commit the latest streamed content into [_messages] before a structural
  /// change, so the list never lags behind what the user already saw live.
  void _syncStreamingIntoList() {
    final pending = _pendingStreamMessage ?? streamingMessage.value;
    if (pending != null && pending.id == _streamingMessageId) {
      _upsertMessage(pending);
    }
  }

  void _clearStreamingChannel() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _pendingStreamMessage = null;
    _streamingMessageId = null;
    streamingMessage.value = null;
  }

  void _upsertMessage(RoomMessage msg) {
    final idx = _messages.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      _messages = List.of(_messages)..[idx] = msg;
    } else {
      _messages = [..._messages, msg];
    }
  }

  // -------------------------------------------------------------------- Mute
  //
  // `Room.mutedUntil` is the source of truth (see its doc comment): the list
  // endpoints populate it server-side, and `openRoom` backfills it from the
  // detail payload's `members` below since `RoomDetailOut` doesn't set it
  // itself. Nothing here needs a side cache anymore.

  /// Mute or unmute the local user's notifications for [roomId].
  ///
  /// [duration] is one of `8h`, `1w`, `forever`, `unmute`. State is taken from
  /// the server's response rather than guessed locally — the backend computes
  /// the expiry (`now + 8h`, the forever-sentinel, …), so an optimistic write
  /// would have to duplicate that arithmetic and could still drift from the
  /// stored value. One round trip, no room refetch: both the listed `Room`
  /// and `_currentRoom` are updated in place so the bell reflects it
  /// immediately.
  Future<void> setMute(String roomId, String duration) async {
    try {
      final member = await _service.setMute(roomId, duration);
      final me = AuthService.instance.cachedUser?.email;
      _rooms = [
        for (final r in _rooms)
          r.id == roomId ? r.withViewerMutedUntil(me, member.mutedUntil) : r,
      ];
      if (_currentRoom?.id == roomId) {
        _currentRoom = _currentRoom!.withViewerMutedUntil(
          me,
          member.mutedUntil,
        );
      }
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ Listing

  Future<void> loadRooms() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _rooms = await _service.listRooms();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Room> createRoom({
    required String name,
    String? description,
    List<String> memberEmails = const [],
  }) async {
    final room = await _service.createRoom(
      name: name,
      description: description,
      memberEmails: memberEmails,
    );
    _rooms = [room, ..._rooms];
    notifyListeners();
    return room;
  }

  Future<void> deleteRoom(String roomId) async {
    await _service.deleteRoom(roomId);
    _rooms = _rooms.where((r) => r.id != roomId).toList();
    if (_currentRoom?.id == roomId) {
      await leaveRoom();
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- Open/close

  Future<void> openRoom(String roomId) async {
    // Close any prior socket
    await leaveRoom();
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final room = await _service.getRoom(roomId);
      // RoomDetailOut doesn't set the top-level `muted_until` itself — derive
      // the viewer's own mute state from the `members` list it does carry, so
      // `Room.mutedUntil`/`isMuted` stay meaningful on the freshly opened room
      // too (not just on rooms that came from the list).
      final me = AuthService.instance.cachedUser?.email;
      _currentRoom = room.withViewerMutedUntil(
        me,
        room.memberFor(me)?.mutedUntil,
      );
      _messages = await _service.listMessages(roomId);
      final socket = _socketFactory(roomId);
      _socket = socket;
      _connectionState = socket.connectionState.value;
      socket.connectionState.addListener(_onConnectionStateChanged);
      _socketSub = socket.events.listen(_onSocketEvent);
      await socket.connect();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> leaveRoom() async {
    _clearTypingState();
    _stopTypingSignal();
    await _socketSub?.cancel();
    _socketSub = null;
    _socket?.connectionState.removeListener(_onConnectionStateChanged);
    await _socket?.close();
    _socket = null;
    _connectionState = RoomConnectionState.closed;
    _wasConnected = false;
    _currentRoom = null;
    _messages = [];
    _online = [];
    _streaming.clear();
    _clearStreamingChannel();
    notifyListeners();
  }

  /// Retry the socket from the failed state (user tapped "Try again").
  void retryConnection() => unawaited(_socket?.retry());

  // ------------------------------------------------------- Connection state

  void _onConnectionStateChanged() {
    final state = _socket?.connectionState.value ?? RoomConnectionState.closed;
    final wasConnectedBefore = _wasConnected;
    _connectionState = state;
    if (state == RoomConnectionState.connected) {
      if (wasConnectedBefore) {
        // A reconnection filled the gap — refetch messages we may have missed
        // while offline.
        unawaited(_refetchMessagesAfterReconnect());
      }
      _wasConnected = true;
    }
    notifyListeners();
  }

  Future<void> _refetchMessagesAfterReconnect() async {
    final room = _currentRoom;
    if (room == null) return;
    try {
      final fresh = await _service.listMessages(room.id);
      // Guard against a room switch mid-fetch.
      if (_currentRoom?.id != room.id) return;
      _messages = fresh;
      _streaming.clear();
      _clearStreamingChannel();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ----------------------------------------------------------------- Sending

  void sendMessage(
    String content, {
    List<ChatAttachment> attachments = const [],
  }) {
    final sock = _socket;
    if (sock == null) return;
    _stopTypingSignal();
    sock.post(content, attachments: attachments);
  }

  // ------------------------------------------------------------ Socket events

  void _onSocketEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'message':
        final msgJson = event['message'] as Map<String, dynamic>?;
        if (msgJson == null) return;
        final msg = RoomMessage.fromJson(msgJson);
        // If the canonical message finalizes the live stream, tear the
        // channel down first so the bubble stops listening to it.
        if (msg.id == _streamingMessageId) {
          _clearStreamingChannel();
        }
        _streaming.remove(msg.id);
        _upsertMessage(msg);
        notifyListeners();
        break;
      case 'stream_start':
        final id = event['message_id'] as String?;
        final agentId = event['agent_id'] as String?;
        if (id == null) return;
        // A new stream takes over the live channel; commit whatever the
        // previous one had into the list first.
        _syncStreamingIntoList();
        final placeholder = RoomMessage(
          id: id,
          roomId: _currentRoom?.id ?? '',
          role: 'assistant',
          senderAgentId: agentId,
          content: '',
          createdAt: DateTime.now(),
          meta: {'agent_name': event['agent_name']},
        );
        _streaming[id] = _StreamingMessage(placeholder, agentId: agentId);
        _streamingMessageId = id;
        _upsertMessage(placeholder);
        _pushStreamingUpdate(placeholder, force: true);
        notifyListeners();
        break;
      case 'chunk':
        final id = event['message_id'] as String?;
        final chunk = event['content'] as String? ?? '';
        if (id == null) return;
        final stream = _streaming[id];
        if (stream == null) return;
        stream.content += chunk;
        if (id == _streamingMessageId) {
          _pushStreamingUpdate(stream.build());
        } else {
          // Non-current concurrent stream: fall back to a structural update.
          _upsertMessage(stream.build());
          notifyListeners();
        }
        break;
      case 'thinking':
      case 'thinking_chunk': // legacy name, pre event-schema unification
        final id = event['message_id'] as String?;
        final chunk = event['content'] as String? ?? '';
        if (id == null) return;
        final stream = _streaming[id];
        if (stream == null) return;
        stream.thinking += chunk;
        if (id == _streamingMessageId) {
          _pushStreamingUpdate(stream.build());
        } else {
          _upsertMessage(stream.build());
          notifyListeners();
        }
        break;
      case 'done':
        // The canonical 'message' event normally arrives first and clears the
        // stream. If it didn't, the turn failed or produced nothing — finalize
        // here so the placeholder doesn't keep showing typing dots forever.
        final id = event['message_id'] as String?;
        if (id == null) return;
        final stream = _streaming.remove(id);
        if (stream == null) return;
        if (id == _streamingMessageId) {
          _syncStreamingIntoList();
          _clearStreamingChannel();
        }
        if (stream.content.isEmpty) {
          // Nothing ever streamed — drop the empty bubble.
          _messages = _messages.where((m) => m.id != id).toList();
        } else {
          _upsertMessage(stream.build());
        }
        notifyListeners();
        break;
      case 'tool':
        // Tool execution progress / result for an agent stream.
        // Update the streaming message's meta so the UI can show tool activity.
        final id = event['message_id'] as String?;
        if (id == null) return;
        final stream = _streaming[id];
        if (stream == null) return;
        final toolName = event['tool_name'] as String? ?? 'tool';
        final status = event['status'] as String? ?? 'started';
        stream.toolEvents.add({
          'tool_name': toolName,
          'status': status,
          'duration_ms': event['duration_ms'],
          'result': event['result'],
        });
        if (id == _streamingMessageId) {
          _pushStreamingUpdate(stream.build());
        } else {
          _upsertMessage(stream.build());
          notifyListeners();
        }
        break;
      case 'presence':
        _online = ((event['online'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        notifyListeners();
        break;
      case 'typing':
        _onTypingEvent(event);
        break;
      case 'error':
        _error = event['error']?.toString();
        notifyListeners();
        break;
    }
  }

  // ------------------------------------------------------------------ Typing

  /// user_id → auto-expiry timer for remote "is typing" state.
  final Map<String, Timer> _typingTimers = {};
  List<String> _typingUsers = [];

  /// User IDs (emails) currently typing, excluding the local user.
  List<String> get typingUsers => List.unmodifiable(_typingUsers);

  bool _localTypingSent = false;
  DateTime _lastTypingSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTypingEvent(Map<String, dynamic> event) {
    final userId = event['user_id'] as String?;
    if (userId == null) return;
    // Never show our own typing back to us.
    final me = AuthService.instance.cachedUser?.email;
    if (me != null && userId == me) return;

    final typing = event['typing'] == true;
    if (typing) {
      _typingTimers[userId]?.cancel();
      _typingTimers[userId] = Timer(_typingExpiry, () {
        _typingTimers.remove(userId);
        _typingUsers = _typingUsers.where((u) => u != userId).toList();
        notifyListeners();
      });
      if (!_typingUsers.contains(userId)) {
        _typingUsers = [..._typingUsers, userId];
        notifyListeners();
      }
    } else {
      _typingTimers.remove(userId)?.cancel();
      if (_typingUsers.contains(userId)) {
        _typingUsers = _typingUsers.where((u) => u != userId).toList();
        notifyListeners();
      }
    }
  }

  /// Call on composer text changes to drive the outbound typing indicator.
  /// Sends `typing:true` at most once per [_typingSendInterval] while the user
  /// is actively typing, and `typing:false` as soon as the field is empty.
  void handleComposerChanged(String text) {
    if (text.trim().isNotEmpty) {
      _startTypingSignal();
    } else {
      _stopTypingSignal();
    }
  }

  /// Call when the composer loses focus.
  void handleComposerBlur() => _stopTypingSignal();

  void _startTypingSignal() {
    final sock = _socket;
    if (sock == null) return;
    final now = DateTime.now();
    if (!_localTypingSent ||
        now.difference(_lastTypingSentAt) >= _typingSendInterval) {
      sock.typing(true);
      _localTypingSent = true;
      _lastTypingSentAt = now;
    }
  }

  void _stopTypingSignal() {
    if (!_localTypingSent) return;
    _localTypingSent = false;
    _socket?.typing(false);
  }

  void _clearTypingState() {
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _typingUsers = [];
  }

  // ---------------------------------------------------------- Agents/Members

  Future<void> addAgent({
    required String name,
    required String model,
    String? systemPrompt,
    String responseMode = 'mention',
    int turnOrder = 0,
    bool isModerator = false,
    String? avatar,
    List<String>? enabledTools,
  }) async {
    final room = _currentRoom;
    if (room == null) return;
    await _service.addAgent(
      room.id,
      name: name,
      model: model,
      systemPrompt: systemPrompt,
      responseMode: responseMode,
      turnOrder: turnOrder,
      isModerator: isModerator,
      avatar: avatar,
      enabledTools: enabledTools,
    );
    _currentRoom = await _service.getRoom(room.id);
    notifyListeners();
  }

  /// Full-field update from the edit dialog. `systemPrompt: null` clears the
  /// prompt and `enabledTools: null` means "all tools" — the backend treats
  /// explicit nulls on nullable columns as clears.
  Future<void> updateAgent(
    String agentId, {
    required String name,
    required String model,
    String? systemPrompt,
    required String responseMode,
    required bool isModerator,
    List<String>? enabledTools,
  }) async {
    final room = _currentRoom;
    if (room == null) return;
    await _service.updateAgent(room.id, agentId, {
      'name': name,
      'model': model,
      'system_prompt': systemPrompt,
      'response_mode': responseMode,
      'is_moderator': isModerator,
      'enabled_tools': enabledTools,
    });
    _currentRoom = await _service.getRoom(room.id);
    notifyListeners();
  }

  Future<void> deleteAgent(String agentId) async {
    final room = _currentRoom;
    if (room == null) return;
    await _service.deleteAgent(room.id, agentId);
    _currentRoom = await _service.getRoom(room.id);
    notifyListeners();
  }

  Future<void> addMember(String email) async {
    final room = _currentRoom;
    if (room == null) return;
    await _service.addMember(room.id, email);
    _currentRoom = await _service.getRoom(room.id);
    notifyListeners();
  }

  Future<void> removeMember(String email) async {
    final room = _currentRoom;
    if (room == null) return;
    await _service.removeMember(room.id, email);
    _currentRoom = await _service.getRoom(room.id);
    notifyListeners();
  }

  @override
  void dispose() {
    _streamFlushTimer?.cancel();
    _clearTypingState();
    _socketSub?.cancel();
    _socket?.connectionState.removeListener(_onConnectionStateChanged);
    _socket?.close();
    streamingMessage.dispose();
    super.dispose();
  }
}

class _StreamingMessage {
  _StreamingMessage(this.base, {this.agentId});

  final RoomMessage base;
  final String? agentId;
  String content = '';
  String thinking = '';
  final List<Map<String, dynamic>> toolEvents = [];

  RoomMessage build() {
    final meta = Map<String, dynamic>.from(base.meta ?? const {});
    if (thinking.isNotEmpty) meta['thinking'] = thinking;
    if (toolEvents.isNotEmpty) meta['tool_events'] = toolEvents;
    return base.copyWith(content: content, meta: meta);
  }
}
