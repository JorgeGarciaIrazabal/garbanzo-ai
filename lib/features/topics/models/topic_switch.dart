import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';

class TopicSwitchResponse {
  TopicSwitchResponse({
    required this.conversationId,
    this.topic,
    required this.contextVersion,
    required this.sessionEpoch,
    required this.archived,
    this.archiveId,
    required this.retainedItems,
    required this.contextStatus,
    required this.idempotencyKey,
    this.nextTurnSummary,
  });

  factory TopicSwitchResponse.fromJson(Map<String, dynamic> json) {
    return TopicSwitchResponse(
      conversationId: json['conversation_id'] as String,
      topic: json['topic'] != null
          ? TopicSwitchTopic.fromJson(json['topic'] as Map<String, dynamic>)
          : null,
      contextVersion: (json['context_version'] as num).toInt(),
      sessionEpoch: (json['session_epoch'] as num?)?.toInt() ?? 0,
      archived: json['archived'] as bool? ?? false,
      archiveId: json['archive_id'] as String?,
      retainedItems: (json['retained_items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ActiveContextItem.fromJson)
          .toList(growable: false),
      contextStatus: _contextStatusFromJson(json['context_status']),
      idempotencyKey: json['idempotency_key'] as String,
      nextTurnSummary: json['next_turn_summary'] as String?,
    );
  }

  final String conversationId;
  final TopicSwitchTopic? topic;
  final int contextVersion;
  final int sessionEpoch;
  final bool archived;
  final String? archiveId;
  final List<ActiveContextItem> retainedItems;
  final TopicContextStatus contextStatus;
  final String idempotencyKey;
  final String? nextTurnSummary;

  static TopicContextStatus _contextStatusFromJson(Object? value) {
    final readiness = switch (value) {
      final Map<String, dynamic> status =>
        (status['readiness'] ?? status['state']) as String?,
      final String readiness => readiness,
      _ => null,
    };
    return TopicContextStatus.values.firstWhere(
      (status) => status.name == readiness,
      orElse: () => TopicContextStatus.empty,
    );
  }
}

class TopicSwitchTopic {
  TopicSwitchTopic({
    required this.id,
    required this.label,
    this.parentId,
    this.parentLabel,
    this.description,
    required this.pinned,
    this.combinedTopics = const [],
  });

  factory TopicSwitchTopic.fromJson(Map<String, dynamic> json) {
    return TopicSwitchTopic(
      id: json['id'] as String,
      label: json['label'] as String,
      parentId: json['parent_id'] as String?,
      parentLabel: json['parent_label'] as String?,
      description: json['description'] as String?,
      pinned: json['pinned'] as bool? ?? false,
      combinedTopics:
          (json['combined_topics'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }

  final String id;
  final String label;
  final String? parentId;
  final String? parentLabel;
  final String? description;
  final bool pinned;
  final List<String> combinedTopics;
}

class TopicArchive {
  TopicArchive({
    required this.id,
    this.topicId,
    this.fromTopicId,
    required this.conversationId,
    required this.messageCount,
    this.shortSummary,
    required this.createdAt,
  });

  factory TopicArchive.fromJson(Map<String, dynamic> json) {
    return TopicArchive(
      id: json['id'] as String,
      topicId: json['topic_id'] as String?,
      fromTopicId: json['from_topic_id'] as String?,
      conversationId: json['conversation_id'] as String,
      messageCount: (json['message_count'] as num).toInt(),
      shortSummary: json['short_summary'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  final String id;
  final String? topicId;
  final String? fromTopicId;
  final String conversationId;
  final int messageCount;
  final String? shortSummary;
  final DateTime createdAt;
}

class TopicArchivePage {
  const TopicArchivePage({
    required this.archive,
    required this.sessionEpoch,
    required this.messages,
    required this.hasMore,
    this.topicLabel,
  });

  factory TopicArchivePage.fromJson(Map<String, dynamic> json) {
    return TopicArchivePage(
      archive: TopicArchive.fromJson(json['archive'] as Map<String, dynamic>),
      topicLabel: json['topic_label'] as String?,
      sessionEpoch: (json['session_epoch'] as num).toInt(),
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessage.fromJson)
          .toList(growable: false),
      hasMore: json['has_more'] as bool? ?? false,
    );
  }

  final TopicArchive archive;
  final String? topicLabel;
  final int sessionEpoch;
  final List<ChatMessage> messages;
  final bool hasMore;

  TopicArchivePage prepend(TopicArchivePage older) => TopicArchivePage(
    archive: archive,
    topicLabel: topicLabel ?? older.topicLabel,
    sessionEpoch: sessionEpoch,
    messages: [...older.messages, ...messages],
    hasMore: older.hasMore,
  );
}
