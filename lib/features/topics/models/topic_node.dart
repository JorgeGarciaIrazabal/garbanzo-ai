/// Discovery modes (`personal`/`explore`) and server evidence origins share
/// one transport enum so unknown rollout combinations remain parseable.
enum TopicOrigin { personal, explore, history, suggested, manual }

enum TopicContextStatus { ready, preparing, limited, live, stale, empty }

class TopicNode {
  const TopicNode({
    required this.id,
    required this.label,
    required this.origin,
    this.parentId,
    this.parentLabel,
    this.score = 0,
    this.signal,
    this.childCount = 0,
    this.children = const [],
    this.starterPrompts = const [],
    this.canStart = true,
    this.description,
    this.contextStatus = TopicContextStatus.empty,
    this.updatedAt,
    this.combinedTopics = const [],
  });

  factory TopicNode.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    final originName = json['origin'] as String? ?? 'history';
    final statusName = switch (json['context_status']) {
      final Map<String, dynamic> value =>
        (value['readiness'] ?? value['state']) as String?,
      final String value => value,
      _ => null,
    };
    return TopicNode(
      id: json['id'] as String,
      parentId: json['parent_id'] as String?,
      parentLabel: json['parent_label'] as String?,
      label: json['label'] as String,
      origin: TopicOrigin.values.firstWhere(
        (value) => value.name == originName,
        orElse: () => TopicOrigin.history,
      ),
      score: (json['score'] as num?)?.toDouble() ?? 0,
      signal: json['signal'] as String?,
      childCount:
          (json['child_count'] as num?)?.toInt() ??
          (rawChildren is List ? rawChildren.length : 0),
      children: rawChildren is List
          ? rawChildren
                .whereType<Map<String, dynamic>>()
                .map(TopicNode.fromJson)
                .toList(growable: false)
          : const [],
      starterPrompts:
          (json['starter_prompts'] as List?)?.whereType<String>().toList() ??
          const [],
      canStart: json['can_start'] as bool? ?? true,
      description: json['description'] as String?,
      contextStatus: TopicContextStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => TopicContextStatus.empty,
      ),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      combinedTopics:
          (json['combined_topics'] as List?)?.whereType<String>().toList() ??
          const [],
    );
  }

  final String id;
  final String? parentId;
  final String? parentLabel;
  final String label;
  final TopicOrigin origin;
  final double score;
  final String? signal;
  final int childCount;
  final List<TopicNode> children;
  final List<String> starterPrompts;
  final bool canStart;
  final String? description;
  final TopicContextStatus contextStatus;
  final DateTime? updatedAt;
  final List<String> combinedTopics;

  Map<String, dynamic> toJson() => {
    'id': id,
    'parent_id': parentId,
    'parent_label': parentLabel,
    'label': label,
    'origin': origin.name,
    'score': score,
    'signal': signal,
    'child_count': childCount,
    'children': children.map((child) => child.toJson()).toList(),
    'starter_prompts': starterPrompts,
    'can_start': canStart,
    'description': description,
    'context_status': contextStatus.name,
    'updated_at': updatedAt?.toIso8601String(),
    'combined_topics': combinedTopics,
  };

  TopicNode copyWith({
    String? id,
    String? parentId,
    String? parentLabel,
    String? label,
    double? score,
    String? signal,
    int? childCount,
    List<TopicNode>? children,
    List<String>? starterPrompts,
    String? description,
    TopicContextStatus? contextStatus,
    List<String>? combinedTopics,
  }) => TopicNode(
    id: id ?? this.id,
    parentId: parentId ?? this.parentId,
    parentLabel: parentLabel ?? this.parentLabel,
    label: label ?? this.label,
    origin: origin,
    score: score ?? this.score,
    signal: signal ?? this.signal,
    childCount: childCount ?? this.childCount,
    children: children ?? this.children,
    starterPrompts: starterPrompts ?? this.starterPrompts,
    canStart: canStart,
    description: description ?? this.description,
    contextStatus: contextStatus ?? this.contextStatus,
    updatedAt: updatedAt,
    combinedTopics: combinedTopics ?? this.combinedTopics,
  );
}

class TopicDriftProposal {
  const TopicDriftProposal({
    required this.detectedTopicId,
    required this.label,
    required this.confidence,
  });

  factory TopicDriftProposal.fromJson(Map<String, dynamic> json) =>
      TopicDriftProposal(
        detectedTopicId:
            (json['detected_topic_id'] ?? json['topic_id']) as String,
        label: (json['label'] ?? '') as String,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final String detectedTopicId;
  final String label;
  final double confidence;
}
