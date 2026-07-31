// Data models for chat rooms.
//
// Plain Dart classes with fromJson/toJson — not generating freezed here to
// keep the build lean; each model can be migrated later if needed.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/mute_util.dart';
import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

@immutable
class RoomAgent {
  final String id;
  final String roomId;
  final String name;
  final String? avatar;
  final String provider;
  final String model;
  final String? systemPrompt;

  /// Reasoning depth for the agent's model; null = provider default (auto).
  final ThinkingLevel? thinkingLevel;
  final String responseMode; // 'mention' | 'always' | 'round_robin' | 'auto'
  final int turnOrder;
  final bool isActive;
  final bool isModerator;
  final List<String>? enabledTools;
  final DateTime createdAt;

  const RoomAgent({
    required this.id,
    required this.roomId,
    required this.name,
    this.avatar,
    required this.provider,
    required this.model,
    this.systemPrompt,
    this.thinkingLevel,
    required this.responseMode,
    required this.turnOrder,
    required this.isActive,
    required this.isModerator,
    this.enabledTools,
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
    thinkingLevel: ThinkingLevel.values.asNameMap()[j['thinking_level']],
    responseMode: j['response_mode'] as String,
    turnOrder: j['turn_order'] as int,
    isActive: j['is_active'] as bool,
    isModerator: j['is_moderator'] as bool,
    enabledTools: (j['enabled_tools'] as List?)
        ?.map((e) => e.toString())
        .toList(),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

@immutable
class RoomMember {
  final String roomId;
  final String userId;

  /// Optional display name for the member. The backend added this field
  /// after the model shipped, so it may be absent/null on older payloads —
  /// callers fall back to [userId] (the email) for display.
  final String? fullName;
  final String? profilePictureB64;
  final String role; // 'owner' | 'member'
  final DateTime joinedAt;

  /// When this member's room notifications stop being muted, or null when they
  /// were never muted. May hold the forever-sentinel — read [isMuted] /
  /// [isMutedForever] instead of comparing this directly.
  final DateTime? mutedUntil;

  const RoomMember({
    required this.roomId,
    required this.userId,
    this.fullName,
    this.profilePictureB64,
    required this.role,
    required this.joinedAt,
    this.mutedUntil,
  });

  /// Display name for the member: [fullName] when present, else the email.
  String get displayName {
    final name = fullName?.trim();
    return (name != null && name.isNotEmpty) ? name : userId;
  }

  /// Whether room notifications are muted for this member right now.
  bool get isMuted => isMuteActive(mutedUntil);

  /// Whether the mute is indefinite ("Always") rather than a timed one.
  bool get isMutedForever => isMuteForever(mutedUntil);

  /// Copy with a new [mutedUntil] — used to keep this member's mute state in
  /// sync with `Room.mutedUntil` after a `setMute` round trip.
  RoomMember withMutedUntil(DateTime? mutedUntil) => RoomMember(
    roomId: roomId,
    userId: userId,
    fullName: fullName,
    profilePictureB64: profilePictureB64,
    role: role,
    joinedAt: joinedAt,
    mutedUntil: mutedUntil,
  );

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
    roomId: j['room_id'] as String,
    userId: j['user_id'] as String,
    fullName: j['full_name'] as String?,
    profilePictureB64: j['profile_picture_b64'] as String?,
    role: j['role'] as String,
    joinedAt: DateTime.parse(j['joined_at'] as String),
    mutedUntil: j['muted_until'] == null
        ? null
        : DateTime.parse(j['muted_until'] as String),
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

  /// The *viewer's own* mute state for this room (`RoomOut.muted_until`).
  ///
  /// `GET /rooms` and `/rooms/search` (`RoomOut`) populate this directly from
  /// the backend, so the room list can badge muted rooms without opening
  /// each one. `GET /rooms/{id}` (`RoomDetailOut`) does not set this field
  /// itself — it carries the full `members` list instead — so
  /// `RoomProvider.openRoom` backfills it from `memberFor(viewerEmail)` right
  /// after fetching, and `setMute` keeps both in sync afterwards. UI code
  /// should always read [mutedUntil] / [isMuted] here rather than reaching
  /// into [members] for the local user's own mute state.
  final DateTime? mutedUntil;

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
    this.mutedUntil,
  });

  /// Whether room notifications are muted for the viewer right now.
  bool get isMuted => isMuteActive(mutedUntil);

  /// The membership row for [email], or null when absent.
  ///
  /// Note [members] is only populated by the room *detail* payload — the list
  /// endpoint (`GET /rooms`) returns `RoomOut`, which carries counts but no
  /// members — so this returns null for rooms that only came from the list.
  RoomMember? memberFor(String? email) {
    if (email == null) return null;
    for (final m in members) {
      if (m.userId == email) return m;
    }
    return null;
  }

  /// Copy with a new viewer [mutedUntil], keeping the matching entry in
  /// [members] (if any, and if [viewerEmail] is known) consistent with it —
  /// so `Room.mutedUntil` and `RoomMember.mutedUntil` never disagree about
  /// the same user after a `setMute` round trip.
  Room withViewerMutedUntil(String? viewerEmail, DateTime? mutedUntil) {
    final updatedMembers = viewerEmail == null
        ? members
        : [
            for (final m in members)
              m.userId == viewerEmail ? m.withMutedUntil(mutedUntil) : m,
          ];
    return Room(
      id: id,
      name: name,
      description: description,
      ownerId: ownerId,
      isPublic: isPublic,
      maxAgentTurnDepth: maxAgentTurnDepth,
      mode: mode,
      createdAt: createdAt,
      updatedAt: updatedAt,
      memberCount: memberCount,
      agentCount: agentCount,
      members: updatedMembers,
      agents: agents,
      mutedUntil: mutedUntil,
    );
  }

  factory Room.fromJson(Map<String, dynamic> j) {
    final members =
        (j['members'] as List?)
            ?.map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];
    final agents =
        (j['agents'] as List?)
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
      mutedUntil: j['muted_until'] == null
          ? null
          : DateTime.parse(j['muted_until'] as String),
    );
  }
}

@immutable
class RoomAudioNote {
  const RoomAudioNote({
    required this.id,
    required this.mimeType,
    required this.durationSeconds,
  });

  final String id;
  final String mimeType;
  final double durationSeconds;

  factory RoomAudioNote.fromJson(Map<String, dynamic> json) => RoomAudioNote(
    id: json['id'] as String,
    mimeType: json['mime_type'] as String? ?? 'audio/wav',
    durationSeconds: (json['duration_seconds'] as num).toDouble(),
  );
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

  RoomMessage copyWith({String? content, Map<String, dynamic>? meta}) =>
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

  /// Attachments stored in [meta]. Images carry their base64 data (so every
  /// member can render them); documents are name-only chips — their text was
  /// appended to [content] server-side.
  List<ChatAttachment> get attachments {
    final raw = meta?['attachments'];
    if (raw is! List) return const [];
    return [
      for (final a in raw.whereType<Map<String, dynamic>>())
        ChatAttachment(
          name: (a['name'] as String?) ?? 'file',
          mimeType: (a['mime_type'] as String?) ?? 'application/octet-stream',
          type: a['type'] == 'image'
              ? AttachmentType.image
              : AttachmentType.document,
          bytes: a['data'] is String
              ? base64Decode(a['data'] as String)
              : Uint8List(0),
        ),
    ];
  }

  RoomAudioNote? get audioNote {
    final raw = meta?['audio_note'];
    if (raw is! Map<String, dynamic>) return null;
    return RoomAudioNote.fromJson(raw);
  }
}
