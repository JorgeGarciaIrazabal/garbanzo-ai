/// A document stored in the user's knowledge base.
class KnowledgeDocument {
  const KnowledgeDocument({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.fileSize,
    required this.status,
    required this.chunkCount,
    required this.createdAt,
    this.errorMessage,
  });

  final String id;
  final String filename;
  final String mimeType;
  final int fileSize;
  final String status; // pending | processing | ready | failed
  final int chunkCount;
  final String? errorMessage;
  final DateTime createdAt;

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'pending' || status == 'processing';
  bool get isFailed => status == 'failed';

  factory KnowledgeDocument.fromJson(Map<String, dynamic> json) {
    return KnowledgeDocument(
      id: json['id'] as String,
      filename: json['filename'] as String,
      mimeType: (json['mime_type'] as String?) ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'pending',
      chunkCount: (json['chunk_count'] as num?)?.toInt() ?? 0,
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
