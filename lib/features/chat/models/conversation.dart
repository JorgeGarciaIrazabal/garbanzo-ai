import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:garbanzo_ai/core/mute_util.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

/// A conversation thread between a user and the AI.
@freezed
abstract class Conversation with _$Conversation {
  const Conversation._();

  const factory Conversation({
    required String id,
    String? title,
    required String model,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(0) int messageCount,
    @Default(true) bool useMemory,
    @Default(true) bool useKnowledgeBase,
    @Default(false) bool isPinned,
    String? contextSummary,
    String? systemPrompt,
    // Reasoning depth for thinking-capable models; null = provider default
    // (thinking auto-enables when the model supports it).
    @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)
    ThinkingLevel? thinkingLevel,
    List<String>? enabledTools,
    List<ChatMessage>? messages,
    // True when `messages` is a windowed page (server was asked for a
    // `message_limit`) and older messages exist — page them in via
    // ChatService.getOlderMessages (B-03).
    @Default(false) bool hasMoreMessages,
    // NULL = not muted. A far-future sentinel value means "muted forever" —
    // see the backend's `mute_util.MUTE_FOREVER`. Read [isMuted] /
    // [isMutedForever] instead of comparing this directly (mirrors
    // `Room.mutedUntil` / `RoomMember.mutedUntil`).
    DateTime? mutedUntil,
    @Default(false) bool isPrimary,
    String? activeTopicId,
    TopicNode? activeTopic,
    @Default(false) bool topicIsPinned,
    @Default(0) int contextVersion,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);

  /// Whether notifications are muted for this conversation right now.
  bool get isMuted => isMuteActive(mutedUntil);

  /// Whether the mute is indefinite ("Always") rather than a timed one.
  bool get isMutedForever => isMuteForever(mutedUntil);

  String get displayTitle {
    if (title != null && title!.isNotEmpty) {
      return title!;
    }
    if (messages != null && messages!.isNotEmpty) {
      final firstUserMessage = messages!.firstWhere(
        (m) => m.isUser,
        orElse: () => messages!.first,
      );
      final content = firstUserMessage.content;
      if (content.length > 50) {
        return '${content.substring(0, 50)}...';
      }
      return content;
    }
    return 'New Conversation';
  }
}

/// A list of conversations with pagination info.
@freezed
abstract class ConversationList with _$ConversationList {
  const ConversationList._();

  const factory ConversationList({
    required List<Conversation> items,
    required int total,
    required int page,
    required int pageSize,
  }) = _ConversationList;

  factory ConversationList.fromJson(Map<String, dynamic> json) =>
      _$ConversationListFromJson(json);

  bool get hasMore => total > page * pageSize;
  int get totalPages => (total / pageSize).ceil();
}
