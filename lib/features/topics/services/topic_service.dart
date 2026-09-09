import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/models/topic_switch.dart';

/// Narrow adapter for the evolving topic API contract.
class TopicService {
  TopicService._();
  static final TopicService instance = TopicService._();

  @visibleForTesting
  TopicService.forTesting();

  final ApiClient _api = ApiClient.instance;

  Future<List<TopicNode>> listTopics(TopicOrigin mode) async {
    final response = await getTopicListResponse(mode);
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
    final body = response.data;
    if (body is! Map<String, dynamic> || body['topics'] is! List<dynamic>) {
      throw const FormatException('Invalid topic list response');
    }
    final raw = body['topics'] as List<dynamic>;
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TopicNode.fromJson)
        .toList(growable: false);
  }

  @visibleForTesting
  Future<Response<dynamic>> getTopicListResponse(TopicOrigin mode) =>
      _api.get('/api/v1/chat/topics', queryParameters: {'mode': mode.name});

  Future<void> setTopicPinned(
    String conversationId, {
    required bool pinned,
    required int contextVersion,
  }) async {
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId/topic',
      data: {'pinned': pinned, 'context_version': contextVersion},
    );
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
  }

  Future<TopicSwitchResponse> switchTopic(
    String conversationId, {
    String? topicId,
    String? label,
    bool archive = true,
    bool retainPinned = true,
    required String idempotencyKey,
    String mode = 'switch',
  }) async {
    if ((topicId == null) == (label == null || label.trim().isEmpty)) {
      throw ArgumentError('Provide exactly one topic ID or label');
    }
    final response = await postTopicSwitch(conversationId, <String, dynamic>{
      ...topicId != null ? {'topic_id': topicId} : {},
      ...label != null ? {'label': label} : {},
      'archive': archive,
      'mode': mode,
      'retain_pinned': retainPinned,
      'idempotency_key': idempotencyKey,
    });
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
    return TopicSwitchResponse.fromJson(response.data as Map<String, dynamic>);
  }

  @visibleForTesting
  Future<Response<dynamic>> postTopicSwitch(
    String conversationId,
    Map<String, dynamic> data,
  ) => _api.post(
    '/api/v1/chat/conversations/$conversationId/topics/switch',
    data: data,
  );

  Future<TopicSwitchResponse> combineTopics(
    String conversationId, {
    String? topicId,
    String? label,
    required String idempotencyKey,
  }) async {
    return switchTopic(
      conversationId,
      topicId: topicId,
      label: label,
      archive: false,
      idempotencyKey: idempotencyKey,
      mode: 'combine',
    );
  }

  Future<List<TopicArchive>> listArchives(String topicId) async {
    final response = await _api.get('/api/v1/chat/topics/$topicId/archives');
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
    final body = response.data as Map<String, dynamic>;
    final raw = (body['archives'] as List<dynamic>? ?? const []);
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TopicArchive.fromJson)
        .toList(growable: false);
  }

  Future<TopicArchivePage> getArchivePage(
    String topicId,
    String archiveId, {
    String? before,
    int limit = 100,
  }) async {
    final response = await _api.get(
      '/api/v1/chat/topics/$topicId/archives/$archiveId',
      queryParameters: {'limit': limit, 'before': ?before},
    );
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Invalid topic archive response');
    }
    return TopicArchivePage.fromJson(body);
  }
}

class TopicServiceException implements Exception {
  const TopicServiceException(this.statusCode);
  final int statusCode;
}
