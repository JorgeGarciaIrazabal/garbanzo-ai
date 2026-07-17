import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';

/// REST client for multi-person chat rooms.
class RoomService {
  RoomService._();
  static final RoomService instance = RoomService._();

  final _api = ApiClient.instance;

  Future<List<Room>> listRooms({int page = 1, int pageSize = 50}) async {
    final resp = await _api.get(
      '/api/v1/rooms',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to list rooms: ${resp.statusCode}');
    }
    final items = (resp.data['items'] as List)
        .map((e) => Room.fromJson(e as Map<String, dynamic>))
        .toList();
    return items;
  }

  Future<Room> createRoom({
    required String name,
    String? description,
    bool isPublic = false,
    int maxAgentTurnDepth = 3,
    List<String> memberEmails = const [],
  }) async {
    final resp = await _api.post(
      '/api/v1/rooms',
      data: {
        'name': name,
        'description': ?description,
        'is_public': isPublic,
        'max_agent_turn_depth': maxAgentTurnDepth,
        'member_emails': memberEmails,
      },
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception('Failed to create room: ${resp.statusCode} ${resp.data}');
    }
    return Room.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Room> getRoom(String roomId) async {
    final resp = await _api.get('/api/v1/rooms/$roomId');
    if (resp.statusCode != 200) {
      throw Exception('Failed to load room: ${resp.statusCode}');
    }
    return Room.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Room> updateRoom(
    String roomId, {
    String? name,
    String? description,
    bool? isPublic,
    int? maxAgentTurnDepth,
    String? ownerId,
  }) async {
    final payload = <String, dynamic>{};
    if (name != null) payload['name'] = name;
    if (description != null) payload['description'] = description;
    if (isPublic != null) payload['is_public'] = isPublic;
    if (maxAgentTurnDepth != null) {
      payload['max_agent_turn_depth'] = maxAgentTurnDepth;
    }
    if (ownerId != null) payload['owner_id'] = ownerId;
    final resp = await _api.patch('/api/v1/rooms/$roomId', data: payload);
    if (resp.statusCode != 200) {
      throw Exception('Failed to update room: ${resp.statusCode}');
    }
    return Room.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteRoom(String roomId) async {
    final resp = await _api.delete('/api/v1/rooms/$roomId');
    if (resp.statusCode != 204) {
      throw Exception('Failed to delete room: ${resp.statusCode}');
    }
  }

  Future<RoomMember> addMember(
    String roomId,
    String email, {
    String role = 'member',
  }) async {
    final resp = await _api.post(
      '/api/v1/rooms/$roomId/members',
      data: {'user_id': email, 'role': role},
    );
    if (resp.statusCode != 201) {
      throw Exception('Failed to add member: ${resp.statusCode} ${resp.data}');
    }
    return RoomMember.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> removeMember(String roomId, String email) async {
    final resp = await _api.delete('/api/v1/rooms/$roomId/members/$email');
    if (resp.statusCode != 204) {
      throw Exception('Failed to remove member: ${resp.statusCode}');
    }
  }

  /// Mute or unmute the current user's notifications for [roomId].
  ///
  /// [duration] is one of `8h`, `1w`, `forever`, `unmute` — validated
  /// server-side by the `RoomMuteUpdate` schema.
  Future<RoomMember> setMute(String roomId, String duration) async {
    final resp = await _api.patch(
      '/api/v1/rooms/$roomId/members/me/mute',
      data: {'duration': duration},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update mute: ${resp.statusCode} ${resp.data}');
    }
    return RoomMember.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<RoomAgent> addAgent(
    String roomId, {
    required String name,
    required String model,
    String provider = 'ollama',
    String? avatar,
    String? systemPrompt,
    ThinkingLevel? thinkingLevel,
    String responseMode = 'mention',
    int turnOrder = 0,
    bool isModerator = false,
    List<String>? enabledTools,
  }) async {
    final resp = await _api.post(
      '/api/v1/rooms/$roomId/agents',
      data: {
        'name': name,
        'model': model,
        'provider': provider,
        'avatar': ?avatar,
        'system_prompt': ?systemPrompt,
        'thinking_level': ?thinkingLevel?.name,
        'response_mode': responseMode,
        'turn_order': turnOrder,
        'is_active': true,
        'is_moderator': isModerator,
        'enabled_tools': ?enabledTools,
      },
    );
    if (resp.statusCode != 201) {
      throw Exception('Failed to add agent: ${resp.statusCode} ${resp.data}');
    }
    return RoomAgent.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<RoomAgent> updateAgent(
    String roomId,
    String agentId,
    Map<String, dynamic> patch,
  ) async {
    final resp = await _api.patch(
      '/api/v1/rooms/$roomId/agents/$agentId',
      data: patch,
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to update agent: ${resp.statusCode}');
    }
    return RoomAgent.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteAgent(String roomId, String agentId) async {
    final resp = await _api.delete('/api/v1/rooms/$roomId/agents/$agentId');
    if (resp.statusCode != 204) {
      throw Exception('Failed to delete agent: ${resp.statusCode}');
    }
  }

  Future<List<RoomMessage>> listMessages(
    String roomId, {
    int page = 1,
    int pageSize = 100,
  }) async {
    final resp = await _api.get(
      '/api/v1/rooms/$roomId/messages',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to list messages: ${resp.statusCode}');
    }
    return (resp.data['items'] as List)
        .map((e) => RoomMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<String> exportMarkdown(String roomId) async {
    final resp = await _api.get(
      '/api/v1/rooms/$roomId/export',
      queryParameters: {'format': 'markdown'},
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to export: ${resp.statusCode}');
    }
    return resp.data.toString();
  }

  Future<List<Room>> search(
    String query, {
    String scope = 'all',
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _api.get(
      '/api/v1/rooms/search',
      queryParameters: {
        'q': query,
        'scope': scope,
        'page': page,
        'page_size': pageSize,
      },
    );
    if (resp.statusCode != 200) {
      throw Exception('Search failed: ${resp.statusCode}');
    }
    return (resp.data['items'] as List)
        .map((e) => Room.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
