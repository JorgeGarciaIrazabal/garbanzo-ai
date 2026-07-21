/// A user-submitted bug report or feature request (idea 14).
///
/// [type] is `bug` or `feature`; [status] flows `open` → `in_progress` →
/// `closed` and is admin-controlled.
class Report {
  const Report({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.description,
    this.metadata,
    this.conversationId,
    this.severity,
    this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String type;
  final String title;
  final String description;
  final Map<String, dynamic>? metadata;
  final String? conversationId;
  final String? severity;
  final String? source;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    type: json['type'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
    conversationId: json['conversation_id'] as String?,
    severity: json['severity'] as String?,
    source: json['source'] as String?,
    status: json['status'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );
}
