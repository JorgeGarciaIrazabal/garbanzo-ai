import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';

class ActiveContextService {
  ActiveContextService._();
  static final ActiveContextService instance = ActiveContextService._();

  @visibleForTesting
  ActiveContextService.forTesting();

  final ApiClient _api = ApiClient.instance;

  Future<ActiveContext> getContext(String conversationId) async {
    final response = await _api.get(
      '/api/v1/chat/conversations/$conversationId/context',
      silent: true,
    );
    if (response.statusCode != 200) {
      throw ActiveContextServiceException(response.statusCode ?? 0);
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
      throw ActiveContextServiceException(response.statusCode ?? 0);
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
      throw ActiveContextServiceException(response.statusCode ?? 0);
    }
    return ((response.data as Map<String, dynamic>)['context_version'] as num)
        .toInt();
  }
}

class ActiveContextServiceException implements Exception {
  const ActiveContextServiceException(this.statusCode);
  final int statusCode;
}
