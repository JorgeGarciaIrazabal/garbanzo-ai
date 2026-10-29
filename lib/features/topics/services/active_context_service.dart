import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';

class ActiveContextService {
  ActiveContextService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final ActiveContextService instance = ActiveContextService();

  @visibleForTesting
  ActiveContextService.forTesting() : this();

  final ApiClient _api;

  Future<ActiveContext> getContext(String conversationId) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId/context',
      silent: true,
    );
    if (response.statusCode != 200) {
      throw ActiveContextServiceException(
        response.statusCode ?? 0,
        detail: apiErrorDetail(response.data),
      );
    }
    return ActiveContext.fromJson(response.data as Map<String, dynamic>);
  }

  Future<ActiveContext> mutateItem(
    String conversationId,
    String itemId, {
    required ActiveContextItemState state,
    required int contextVersion,
  }) async {
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId/context/items/$itemId',
      data: {'state': state.name, 'context_version': contextVersion},
    );
    if (response.statusCode != 200) {
      throw ActiveContextServiceException(
        response.statusCode ?? 0,
        detail: apiErrorDetail(response.data),
      );
    }
    final version =
        ((response.data as Map<String, dynamic>)['context_version'] as num)
            .toInt();
    return ActiveContext(
      conversationId: conversationId,
      version: version,
      readiness: ActiveContextReadiness.ready,
    );
  }

  Future<int> addSource(
    String conversationId, {
    required String sourceType,
    required String sourceId,
    required int contextVersion,
  }) async {
    final response = await _api.post(
      '/api/v1/chat/conversations/$conversationId/context/items',
      data: {
        'source_type': sourceType,
        'source_id': sourceId,
        'context_version': contextVersion,
      },
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw ActiveContextServiceException(
        response.statusCode ?? 0,
        detail: apiErrorDetail(response.data),
      );
    }
    return ((response.data as Map<String, dynamic>)['context_version'] as num)
        .toInt();
  }
}

class ActiveContextServiceException implements Exception {
  const ActiveContextServiceException(this.statusCode, {this.detail});
  final int statusCode;
  final String? detail;

  @override
  String toString() => detail == null || detail!.isEmpty
      ? 'ActiveContextServiceException ($statusCode)'
      : 'API Error ($statusCode): $detail';
}
