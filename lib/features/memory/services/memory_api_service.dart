import 'package:dio/dio.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/memory/models/memory.dart';

/// Service for interacting with the Memory API.
///
/// All HTTP calls are routed through [ApiClient] so that base-URL resolution,
/// auth headers, and JSON encoding stay in one place.
class MemoryApiService {
  MemoryApiService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final MemoryApiService instance = MemoryApiService();

  final ApiClient _api;

  // ==========================================================================
  // Memory CRUD operations
  // ==========================================================================

  /// List all active memories for the authenticated user.
  Future<List<Memory>> listMemories() async {
    final response = await _api.get('/api/v1/memories');

    if (response.statusCode == 200) {
      final data = response.data as List;
      return data
          .map((e) => Memory.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw _handleError(response);
  }

  /// Get a specific memory by ID.
  Future<Memory> getMemory(String memoryId) async {
    final response = await _api.get('/api/v1/memories/$memoryId');

    if (response.statusCode == 200) {
      return Memory.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  /// Create a new memory.
  Future<Memory> createMemory({
    required String content,
    String? sourceConversationId,
  }) async {
    final response = await _api.post(
      '/api/v1/memories',
      data: {
        'content': content,
        'source_conversation_id': sourceConversationId,
      },
    );

    if (response.statusCode == 201) {
      return Memory.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  /// Update a memory's content or active status.
  Future<Memory> updateMemory({
    required String memoryId,
    String? content,
    bool? isActive,
  }) async {
    final response = await _api.patch(
      '/api/v1/memories/$memoryId',
      data: {'content': ?content, 'is_active': ?isActive},
    );

    if (response.statusCode == 200) {
      return Memory.fromJson(response.data as Map<String, dynamic>);
    }

    throw _handleError(response);
  }

  /// Deactivate (soft-delete) a memory.
  Future<void> deactivateMemory(String memoryId) async {
    final response = await _api.delete('/api/v1/memories/$memoryId');

    if (response.statusCode != 204) {
      throw _handleError(response);
    }
  }

  // ==========================================================================
  // Error handling
  // ==========================================================================

  Exception _handleError(Response<dynamic> response) =>
      apiResponseError(response, operation: 'Memory request failed');
}
