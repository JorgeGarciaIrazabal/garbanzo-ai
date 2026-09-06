import 'package:garbanzo_ai/features/topics/models/topic_node.dart';

enum ActiveContextReadiness { ready, preparing, limited }

enum ActiveContextItemState { dynamic, pinned, excluded }

class ActiveContextItem {
  const ActiveContextItem({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.state,
    required this.reason,
    this.title,
    this.preview,
    this.summary,
    this.categoryLabel,
    this.tokenCount = 0,
  });

  factory ActiveContextItem.fromJson(Map<String, dynamic> json) {
    final meta = json['source_meta'] as Map<String, dynamic>?;
    final summaryVal =
        json['summary'] as String? ??
        json['display_text'] as String? ??
        meta?['summary'] as String?;
    final previewVal =
        json['preview'] as String? ??
        meta?['preview'] as String? ??
        json['content'] as String? ??
        meta?['content'] as String?;
    final titleVal = json['title'] as String? ?? meta?['title'] as String?;
    final reasonVal = json['reason'] as String? ?? '';

    return ActiveContextItem(
      id: json['id'] as String,
      sourceType: json['source_type'] as String? ?? 'message',
      sourceId: json['source_id'] as String? ?? '',
      state: ActiveContextItemState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => ActiveContextItemState.dynamic,
      ),
      reason: reasonVal,
      title: titleVal,
      preview: previewVal,
      summary: summaryVal,
      categoryLabel: json['category_label'] as String?,
      tokenCount: (json['token_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String sourceType;
  final String sourceId;
  final ActiveContextItemState state;
  final String reason;
  final String? title;
  final String? preview;
  final String? summary;
  final String? categoryLabel;
  final int tokenCount;

  String get highLevelSentence => summary ?? preview ?? title ?? reason;

  ActiveContextItem copyWith({ActiveContextItemState? state}) =>
      ActiveContextItem(
        id: id,
        sourceType: sourceType,
        sourceId: sourceId,
        state: state ?? this.state,
        reason: reason,
        title: title,
        preview: preview,
        summary: summary,
        categoryLabel: categoryLabel,
        tokenCount: tokenCount,
      );
}

class ContextSection {
  const ContextSection({
    required this.id,
    required this.title,
    this.icon = 'info',
    this.sentences = const [],
  });

  factory ContextSection.fromJson(Map<String, dynamic> json) => ContextSection(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    icon: json['icon'] as String? ?? 'info',
    sentences:
        (json['sentences'] as List?)?.whereType<String>().toList() ?? const [],
  );

  final String id;
  final String title;
  final String icon;
  final List<String> sentences;
}

class ActiveContext {
  const ActiveContext({
    required this.conversationId,
    required this.version,
    required this.readiness,
    this.topic,
    this.topicPinned = false,
    this.summary = '',
    this.topicDescription,
    this.contextSummary,
    this.contextSections = const [],
    this.tokenCount = 0,
    this.tokenBudget = 0,
    this.items = const [],
    this.liveDeltaCount = 0,
  });

  factory ActiveContext.fromJson(Map<String, dynamic> json) {
    final rawTopic = json['topic'] ?? json['active_topic'];
    final status = json['status'] as Map<String, dynamic>?;
    final readinessName =
        status?['readiness'] as String? ?? json['readiness'] as String?;
    final groupedItems = <dynamic>[
      ...?json['pinned_items'] as List?,
      ...?json['dynamic_items'] as List?,
      ...?json['excluded_items'] as List?,
    ];
    final rawItems = json['items'] as List? ?? groupedItems;
    final rawSections = json['context_sections'] as List?;

    final topicNode = rawTopic is Map<String, dynamic>
        ? TopicNode.fromJson({
            'origin': 'history',
            'score': 1,
            'child_count': 0,
            'children': const [],
            'starter_prompts': const [],
            'can_start': true,
            'description': json['topic_description'] ?? rawTopic['description'],
            ...rawTopic,
          })
        : null;

    final topicDesc =
        json['topic_description'] as String? ??
        (rawTopic is Map<String, dynamic>
            ? rawTopic['description'] as String?
            : null) ??
        topicNode?.description;

    final summaryText =
        json['context_summary'] as String? ??
        json['next_turn_summary'] as String? ??
        json['summary'] as String? ??
        '';

    return ActiveContext(
      conversationId: json['conversation_id'] as String? ?? '',
      version:
          (json['context_version'] as num?)?.toInt() ??
          (json['version'] as num?)?.toInt() ??
          0,
      readiness: ActiveContextReadiness.values.firstWhere(
        (value) => value.name == readinessName,
        orElse: () => readinessName == 'limited' || json['limited'] == true
            ? ActiveContextReadiness.limited
            : readinessName == 'preparing'
            ? ActiveContextReadiness.preparing
            : ActiveContextReadiness.ready,
      ),
      topic: topicNode,
      topicPinned:
          json['topic_is_pinned'] as bool? ??
          (rawTopic is Map<String, dynamic>
              ? rawTopic['pinned'] as bool? ?? false
              : false),
      summary: summaryText,
      topicDescription: topicDesc,
      contextSummary: summaryText,
      contextSections: rawSections != null
          ? rawSections
                .whereType<Map<String, dynamic>>()
                .map(ContextSection.fromJson)
                .toList(growable: false)
          : const [],
      tokenCount: (json['token_count'] as num?)?.toInt() ?? 0,
      tokenBudget: (json['token_budget'] as num?)?.toInt() ?? 0,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(ActiveContextItem.fromJson)
          .toList(growable: false),
      liveDeltaCount:
          (json['live_delta_count'] as num?)?.toInt() ??
          (status?['live_delta_count'] as num?)?.toInt() ??
          0,
    );
  }

  final String conversationId;
  final int version;
  final ActiveContextReadiness readiness;
  final TopicNode? topic;
  final bool topicPinned;
  final String summary;
  final String? topicDescription;
  final String? contextSummary;
  final List<ContextSection> contextSections;
  final int tokenCount;
  final int tokenBudget;
  final List<ActiveContextItem> items;
  final int liveDeltaCount;

  List<ActiveContextItem> get pinnedItems => items
      .where((item) => item.state == ActiveContextItemState.pinned)
      .toList(growable: false);

  List<ActiveContextItem> get dynamicItems => items
      .where((item) => item.state == ActiveContextItemState.dynamic)
      .toList(growable: false);

  ActiveContext copyWith({
    int? version,
    ActiveContextReadiness? readiness,
    TopicNode? topic,
    bool? topicPinned,
    String? summary,
    String? topicDescription,
    String? contextSummary,
    List<ContextSection>? contextSections,
    int? tokenCount,
    int? tokenBudget,
    List<ActiveContextItem>? items,
    int? liveDeltaCount,
  }) => ActiveContext(
    conversationId: conversationId,
    version: version ?? this.version,
    readiness: readiness ?? this.readiness,
    topic: topic ?? this.topic,
    topicPinned: topicPinned ?? this.topicPinned,
    summary: summary ?? this.summary,
    topicDescription: topicDescription ?? this.topicDescription,
    contextSummary: contextSummary ?? this.contextSummary,
    contextSections: contextSections ?? this.contextSections,
    tokenCount: tokenCount ?? this.tokenCount,
    tokenBudget: tokenBudget ?? this.tokenBudget,
    items: items ?? this.items,
    liveDeltaCount: liveDeltaCount ?? this.liveDeltaCount,
  );
}
