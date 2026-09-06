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
    final response = await _api.get(
      '/api/v1/chat/topics',
      queryParameters: {'mode': mode.name},
    );
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
    final body = response.data;
    final raw = switch (body) {
      final List<dynamic> value => value,
      final Map<String, dynamic> value =>
        (value['items'] ?? value['topics']) as List<dynamic>? ?? const [],
      _ => const <dynamic>[],
    };
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TopicNode.fromJson)
        .toList(growable: false);
  }

  Future<void> activateTopic(
    String conversationId, {
    String? topicId,
    String? label,
  }) async {
    final response = await _api.post(
      '/api/v1/chat/conversations/$conversationId/topics/activate',
      data: {'topic_id': ?topicId, 'label': ?label},
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
  }

  Future<void> prepare(String topicId) async {
    final response = await _api.post('/api/v1/chat/topics/$topicId/prepare');
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
  }

  Future<void> setTopicPinned(
    String conversationId, {
    required bool pinned,
    required int contextVersion,
  }) async {
    final response = await _api.patch(
      '/api/v1/chat/conversations/$conversationId/topic',
      data: {'pinned': pinned},
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
    int carryoverMaxItems = 5,
    int carryoverMaxTokens = 400,
    String mode = 'switch',
  }) async {
    final response = await _api.post(
      '/api/v1/chat/conversations/$conversationId/topics/switch',
      data: <String, dynamic>{
        ...topicId != null ? {'topic_id': topicId} : {},
        ...label != null ? {'label': label} : {},
        'archive': archive,
        'mode': mode,
        'carryover': {
          'enabled': carryoverMaxItems > 0,
          'max_items': carryoverMaxItems > 0 ? carryoverMaxItems : 5,
          'max_tokens': carryoverMaxTokens,
        },
      },
    );
    if (response.statusCode != 200) {
      throw TopicServiceException(response.statusCode ?? 0);
    }
    return TopicSwitchResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<TopicSwitchResponse> combineTopics(
    String conversationId, {
    String? topicId,
    String? label,
  }) async {
    return switchTopic(
      conversationId,
      topicId: topicId,
      label: label,
      archive: false,
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
}

class TopicServiceException implements Exception {
  const TopicServiceException(this.statusCode);
  final int statusCode;
}
