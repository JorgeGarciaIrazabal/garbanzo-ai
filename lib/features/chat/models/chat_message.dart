/// A single message in a chat conversation.
class ChatMessage {
  final String id;
  final String role; // 'user', 'assistant', or 'system'
  final String content;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.metadata,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      // API serialises the field as 'meta'; 'metadata' kept for compatibility
      metadata: (json['meta'] ?? json['metadata']) as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  ChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? createdAt,
    Map<String, dynamic>? metadata,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      metadata: metadata ?? this.metadata,
    );
  }

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isSystem => role == 'system';
}

/// A chunk of a streaming chat response.
class ChatResponseChunk {
  final String type; // 'chunk', 'done', or 'error'
  final String? content;
  final String? error;
  final Map<String, dynamic>? metadata;

  const ChatResponseChunk({
    required this.type,
    this.content,
    this.error,
    this.metadata,
  });

  factory ChatResponseChunk.fromJson(Map<String, dynamic> json) {
    return ChatResponseChunk(
      type: json['type'] as String,
      content: json['content'] as String?,
      error: json['error'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  bool get isChunk => type == 'chunk';
  bool get isThinking => type == 'thinking';
  bool get isDone => type == 'done';
  bool get isError => type == 'error';
}
