// Data models for chat rooms.
//
// Plain Dart classes with fromJson/toJson — not generating freezed here to
// keep the build lean; each model can be migrated later if needed.

import 'package:flutter/foundation.dart';

@immutable
class RoomAgent {
  final String id;
  final String roomId;
  final String name;
  final String? avatar;
  final String provider;
  final String model;
  final String? systemPrompt;
  final String responseMode; // 'mention' | 'always' | 'round_robin'
  final int turnOrder;
  final bool isActive;
  final bool isModerator;
  final DateTime createdAt;

  const RoomAgent({
    required this.id,
    required this.roomId,
    required this.name,
    this.avatar,
    required this.provider,
    required this.model,
    this.systemPrompt,
    required this.responseMode,
    required this.turnOrder,
    required this.isActive,
    required this.isModerator,
    required this.createdAt,
  });

  factory RoomAgent.fromJson(Map<String, dynamic> j) => RoomAgent(
        id: j['id'] as String,
        roomId: j['room_id'] as String,
        name: j['name'] as String,
        avatar: j['avatar'] as String?,
        provider: j['provider'] as String,
        model: j['model'] as String,
        systemPrompt: j['system_prompt'] as String?,
        responseMode: j['response_mode'] as String,
        turnOrder: j['turn_order'] as int,
        isActive: j['is_active'] as bool,
        isModerator: j['is_moderator'] as bool,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

@immutable
class RoomMember {
  final String roomId;
  final String userId;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;

  const RoomMember({
    required this.roomId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        roomId: j['room_id'] as String,
        userId: j['user_id'] as String,
        role: j['role'] as String,
        joinedAt: DateTime.parse(j['joined_at'] as String),
      );
}

@immutable
class Room {
  final String id;
  final String name;
  final String? description;
  final String ownerId;
  final bool isPublic;
  final int maxAgentTurnDepth;
  final String mode; // 'chat' | 'debate'
  final DateTime createdAt;
  final DateTime updatedAt;
  final int memberCount;
  final int agentCount;
  final List<RoomMember> members;
  final List<RoomAgent> agents;

  const Room({
    required this.id,
    required this.name,
    this.description,
    required this.ownerId,
    required this.isPublic,
    required this.maxAgentTurnDepth,
    required this.mode,
    required this.createdAt,
    required this.updatedAt,
    required this.memberCount,
    required this.agentCount,
    this.members = const [],
    this.agents = const [],
  });

  factory Room.fromJson(Map<String, dynamic> j) {
    final members = (j['members'] as List?)
            ?.map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];
    final agents = (j['agents'] as List?)
            ?.map((a) => RoomAgent.fromJson(a as Map<String, dynamic>))
            .toList() ??
        const [];
    return Room(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String?,
      ownerId: j['owner_id'] as String,
      isPublic: j['is_public'] as bool,
      maxAgentTurnDepth: j['max_agent_turn_depth'] as int,
      mode: j['mode'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      updatedAt: DateTime.parse(j['updated_at'] as String),
      memberCount: j['member_count'] as int? ?? members.length,
      agentCount: j['agent_count'] as int? ?? agents.length,
      members: members,
      agents: agents,
    );
  }
}

@immutable
class RoomMessage {
  final String id;
  final String roomId;
  final String role;
  final String? senderUserId;
  final String? senderAgentId;
  final String content;
  final Map<String, dynamic>? meta;
  final DateTime createdAt;

  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.role,
    this.senderUserId,
    this.senderAgentId,
    required this.content,
    this.meta,
    required this.createdAt,
  });

  RoomMessage copyWith({
    String? content,
    Map<String, dynamic>? meta,
  }) =>
      RoomMessage(
        id: id,
        roomId: roomId,
        role: role,
        senderUserId: senderUserId,
        senderAgentId: senderAgentId,
        content: content ?? this.content,
        meta: meta ?? this.meta,
        createdAt: createdAt,
      );

  factory RoomMessage.fromJson(Map<String, dynamic> j) => RoomMessage(
        id: j['id'] as String,
        roomId: j['room_id'] as String,
        role: j['role'] as String,
        senderUserId: j['sender_user_id'] as String?,
        senderAgentId: j['sender_agent_id'] as String?,
        content: j['content'] as String,
        meta: j['meta'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
