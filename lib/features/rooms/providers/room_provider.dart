import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/features/rooms/services/room_socket_service.dart';

/// Tracks the user's list of rooms and the currently open room.
class RoomProvider extends ChangeNotifier {
  final _service = RoomService.instance;

  List<Room> _rooms = [];
  Room? _currentRoom;
  List<RoomMessage> _messages = [];
  List<String> _online = [];
  RoomSocketService? _socket;
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  bool _loading = false;
  String? _error;

  /// In-progress agent streams keyed by message_id so chunks can accumulate.
  final Map<String, _StreamingMessage> _streaming = {};

  List<Room> get rooms => List.unmodifiable(_rooms);
  Room? get currentRoom => _currentRoom;
  List<RoomMessage> get messages => List.unmodifiable(_messages);
  List<String> get onlineUsers => List.unmodifiable(_online);
  bool get loading => _loading;
  String? get error => _error;

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
      _currentRoom = await _service.getRoom(roomId);
      _messages = await _service.listMessages(roomId);
      _socket = RoomSocketService(roomId);
      await _socket!.connect();
      _socketSub = _socket!.events.listen(_onSocketEvent);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> leaveRoom() async {
    await _socketSub?.cancel();
    _socketSub = null;
    await _socket?.close();
    _socket = null;
    _currentRoom = null;
    _messages = [];
    _online = [];
    _streaming.clear();
    notifyListeners();
  }

  // ----------------------------------------------------------------- Sending

  void sendMessage(String content) {
    final sock = _socket;
    if (sock == null) return;
    sock.post(content);
  }

  // ------------------------------------------------------------ Socket events

  void _onSocketEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'message':
        final msgJson = event['message'] as Map<String, dynamic>?;
        if (msgJson == null) return;
        final msg = RoomMessage.fromJson(msgJson);
        // If we had a streaming placeholder, replace it; else append.
        final idx = _messages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          _messages = List.of(_messages)..[idx] = msg;
        } else {
          _messages = [..._messages, msg];
        }
        _streaming.remove(msg.id);
        notifyListeners();
        break;
      case 'stream_start':
        final id = event['message_id'] as String?;
        final agentId = event['agent_id'] as String?;
        if (id == null) return;
        _streaming[id] = _StreamingMessage(agentId: agentId);
        final placeholder = RoomMessage(
          id: id,
          roomId: _currentRoom?.id ?? '',
          role: 'assistant',
          senderAgentId: agentId,
          content: '',
          createdAt: DateTime.now(),
          meta: {'agent_name': event['agent_name']},
        );
        _messages = [..._messages, placeholder];
        notifyListeners();
        break;
      case 'chunk':
        final id = event['message_id'] as String?;
        final chunk = event['content'] as String? ?? '';
        if (id == null) return;
        final stream = _streaming[id];
        if (stream == null) return;
        stream.content += chunk;
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx >= 0) {
          _messages = List.of(_messages)
            ..[idx] = _messages[idx].copyWith(content: stream.content);
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
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx >= 0) {
          final existing = _messages[idx];
          final newMeta = Map<String, dynamic>.from(existing.meta ?? const {});
          newMeta['thinking'] = stream.thinking;
          _messages = List.of(_messages)
            ..[idx] = existing.copyWith(meta: newMeta);
          notifyListeners();
        }
        break;
      case 'done':
        // The final 'message' event updates with canonical content; nothing
        // special to do here.
        break;
      case 'presence':
        _online = ((event['online'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        notifyListeners();
        break;
      case 'error':
        _error = event['error']?.toString();
        notifyListeners();
        break;
    }
  }

  // ----------------------------------------------------------------- Agents/Members

  Future<void> addAgent({
    required String name,
    required String model,
    String? systemPrompt,
    String responseMode = 'mention',
    int turnOrder = 0,
    bool isModerator = false,
    String? avatar,
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
    );
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
    _socketSub?.cancel();
    _socket?.close();
    super.dispose();
  }
}

class _StreamingMessage {
  final String? agentId;
  String content = '';
  String thinking = '';
  _StreamingMessage({this.agentId});
}
