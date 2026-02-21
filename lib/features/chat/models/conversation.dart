import 'chat_message.dart';

/// A conversation thread between a user and the AI.
class Conversation {
  final String id;
  final String? title;
  final String model;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;
  final List<ChatMessage>? messages;

  const Conversation({
    required this.id,
    this.title,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.messages,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String?,
      model: json['model'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      messageCount: json['message_count'] as int? ?? 0,
      messages: (json['messages'] as List<dynamic>?)
          ?.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'model': model,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'message_count': messageCount,
      'messages': messages?.map((m) => m.toJson()).toList(),
    };
  }

  Conversation copyWith({
    String? id,
    String? title,
    String? model,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? messageCount,
    List<ChatMessage>? messages,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
      messages: messages ?? this.messages,
    );
  }

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
class ConversationList {
  final List<Conversation> items;
  final int total;
  final int page;
  final int pageSize;

  const ConversationList({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory ConversationList.fromJson(Map<String, dynamic> json) {
    return ConversationList(
      items: (json['items'] as List<dynamic>)
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }

  bool get hasMore => total > page * pageSize;
  int get totalPages => (total / pageSize).ceil();
}
