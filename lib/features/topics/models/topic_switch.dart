import 'package:garbanzo_ai/features/topics/models/active_context.dart';

class TopicSwitchResponse {
  TopicSwitchResponse({
    required this.conversationId,
    this.topic,
    required this.contextVersion,
    required this.archived,
    this.archiveId,
    required this.carryover,
    this.nextTurnSummary,
  });

  factory TopicSwitchResponse.fromJson(Map<String, dynamic> json) {
    return TopicSwitchResponse(
      conversationId: json['conversation_id'] as String,
      topic: json['topic'] != null
          ? TopicSwitchTopic.fromJson(json['topic'] as Map<String, dynamic>)
          : null,
      contextVersion: (json['context_version'] as num).toInt(),
      archived: json['archived'] as bool? ?? false,
      archiveId: json['archive_id'] as String?,
      carryover: (json['carryover'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ActiveContextItem.fromJson)
          .toList(growable: false),
      nextTurnSummary: json['next_turn_summary'] as String?,
    );
  }

  final String conversationId;
  final TopicSwitchTopic? topic;
  final int contextVersion;
  final bool archived;
  final String? archiveId;
  final List<ActiveContextItem> carryover;
  final String? nextTurnSummary;
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
