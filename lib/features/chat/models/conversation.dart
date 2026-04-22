import 'package:freezed_annotation/freezed_annotation.dart';

import 'chat_message.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

/// A conversation thread between a user and the AI.
@freezed
class Conversation with _$Conversation {
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
    List<String>? enabledTools,
    List<ChatMessage>? messages,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);

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
class ConversationList with _$ConversationList {
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
