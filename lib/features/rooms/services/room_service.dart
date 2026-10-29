import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/rooms/models/room_models.dart';

/// REST client for multi-person chat rooms.
class RoomService {
  RoomService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final RoomService instance = RoomService();

  final ApiClient _api;

  Future<List<Room>> listRooms({int page = 1, int pageSize = 50}) async {
    final resp = await _api.get(
      '/api/v1/rooms',
      queryParameters: {'page': page, 'page_size': pageSize},
    );
    expectStatus(resp, const {200}, operation: 'Failed to list rooms');
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
    expectStatus(resp, const {200, 201}, operation: 'Failed to create room');
    return Room.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Room> getRoom(String roomId) async {
    final resp = await _api.get('/api/v1/rooms/$roomId');
    expectStatus(resp, const {200}, operation: 'Failed to load room');
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
    expectStatus(resp, const {200}, operation: 'Failed to update room');
    return Room.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteRoom(String roomId) async {
    final resp = await _api.delete('/api/v1/rooms/$roomId');
    expectStatus(resp, const {204}, operation: 'Failed to delete room');
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
    expectStatus(resp, const {201}, operation: 'Failed to add member');
    return RoomMember.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> removeMember(String roomId, String email) async {
    final resp = await _api.delete('/api/v1/rooms/$roomId/members/$email');
    expectStatus(resp, const {204}, operation: 'Failed to remove member');
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
    expectStatus(resp, const {200}, operation: 'Failed to update mute');
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
    expectStatus(resp, const {201}, operation: 'Failed to add agent');
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
    expectStatus(resp, const {200}, operation: 'Failed to update agent');
    return RoomAgent.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteAgent(String roomId, String agentId) async {
    final resp = await _api.delete('/api/v1/rooms/$roomId/agents/$agentId');
    expectStatus(resp, const {204}, operation: 'Failed to delete agent');
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
    expectStatus(resp, const {200}, operation: 'Failed to list messages');
    return (resp.data['items'] as List)
        .map((e) => RoomMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RoomMessage> postAudioNote(
    String roomId,
    Uint8List audioBytes, {
    String filename = 'audio-note.wav',
  }) async {
    final response = await _api.postMultipart(
      '/api/v1/rooms/$roomId/audio-notes',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(audioBytes, filename: filename),
      }),
    );
    expectStatus(response, const {201}, operation: 'Failed to post audio note');
    final data = response.data as Map<String, dynamic>;
    return RoomMessage.fromJson(data['message'] as Map<String, dynamic>);
  }

  Future<Uint8List> loadAudioNote(String roomId, String noteId) async {
    final response = await _api.getBytes(
      '/api/v1/rooms/$roomId/audio-notes/$noteId',
    );
    if (response.statusCode != 200 || response.data == null) {
      throw apiResponseError(response, operation: 'Failed to load audio note');
    }
    return Uint8List.fromList(response.data!);
  }

  Future<String> exportMarkdown(String roomId) async {
    final resp = await _api.get(
      '/api/v1/rooms/$roomId/export',
      queryParameters: {'format': 'markdown'},
    );
    expectStatus(resp, const {200}, operation: 'Failed to export');
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
    expectStatus(resp, const {200}, operation: 'Search failed');
    return (resp.data['items'] as List)
        .map((e) => Room.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
