import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/knowledge_base/models/knowledge_document.dart';

class KnowledgeBaseService {
  KnowledgeBaseService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final KnowledgeBaseService instance = KnowledgeBaseService();

  final ApiClient _api;

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
        contentType: mimeType == null ? null : DioMediaType.parse(mimeType),
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

  Exception _handleError(Response<dynamic> response) =>
      apiResponseError(response, operation: 'Knowledge base request failed');
}
