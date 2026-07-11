import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/knowledge_base/models/knowledge_document.dart';

class KnowledgeBaseService {
  KnowledgeBaseService._();
  static final KnowledgeBaseService instance = KnowledgeBaseService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<KnowledgeDocument>> listDocuments() async {
    final response = await _api.get('/api/v1/kb/documents');
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? [];
      return items
          .map((e) => KnowledgeDocument.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw _handleError(response);
  }

  Future<KnowledgeDocument> uploadDocument({
    required String filename,
    required List<int> bytes,
    String? mimeType,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mimeType == null
            ? null
            : DioMediaType.parse(mimeType),
      ),
    });
    final response = await _api.postMultipart(
      '/api/v1/kb/documents',
      data: formData,
    );
    if (response.statusCode == 201) {
      return KnowledgeDocument.fromJson(response.data as Map<String, dynamic>);
    }
    throw _handleError(response);
  }

  Future<KnowledgeDocument> getDocument(String documentId) async {
    final response = await _api.get('/api/v1/kb/documents/$documentId');
    if (response.statusCode == 200) {
      return KnowledgeDocument.fromJson(response.data as Map<String, dynamic>);
    }
    throw _handleError(response);
  }

  Future<void> deleteDocument(String documentId) async {
    final response = await _api.delete('/api/v1/kb/documents/$documentId');
    if (response.statusCode != 204) {
      throw _handleError(response);
    }
  }

  Exception _handleError(Response response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail']?.toString() ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    }
    return Exception('API Error (${response.statusCode}): $body');
  }
}
