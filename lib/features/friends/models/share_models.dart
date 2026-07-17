/// A style or prompt template a friend shared, waiting for accept/decline.
class SharedItem {
  const SharedItem({
    required this.id,
    required this.senderEmail,
    required this.kind,
    required this.payload,
    this.createdAt,
  });

  final String id;
  final String senderEmail;

  /// 'style' or 'prompt'.
  final String kind;

  /// The snapshot taken at share time (name, content, …).
  final Map<String, dynamic> payload;

  final DateTime? createdAt;

  String get name => (payload['name'] as String?) ?? '(unnamed)';

  factory SharedItem.fromJson(Map<String, dynamic> json) => SharedItem(
    id: (json['id'] as String?) ?? '',
    senderEmail: (json['sender_email'] as String?) ?? '',
    kind: (json['kind'] as String?) ?? 'prompt',
    payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
  );
}
