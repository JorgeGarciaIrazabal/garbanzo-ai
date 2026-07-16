import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

/// Client for the `/api/v1/styles` endpoints.
class StyleService {
  StyleService._();
  static final StyleService instance = StyleService._();

  /// For tests only: lets a fake subclass exist outside this library.
  @visibleForTesting
  StyleService.forTesting();

  final ApiClient _api = ApiClient.instance;

  Future<List<Style>> listStyles() async {
    final response = await _api.get('/api/v1/styles');
    if (response.statusCode == 200) {
      final data = response.data as List<dynamic>;
      return data
          .map((e) => Style.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to list styles (${response.statusCode})');
  }

  Future<Style> createStyle({
    required String name,
    required String modelId,
    ThinkingLevel? thinkingLevel,
    String? systemPromptTemplateId,
    bool isDefault = false,
  }) async {
    final response = await _api.post(
      '/api/v1/styles',
      data: {
        'name': name,
        'model_id': modelId,
        'thinking_level': ?thinkingLevel?.name,
        'system_prompt_template_id': ?systemPromptTemplateId,
        'is_default': isDefault,
      },
    );
    if (response.statusCode == 201) {
      return Style.fromJson(response.data as Map<String, dynamic>);
    }
    throw Exception('Failed to create style (${response.statusCode})');
  }

  /// Partial update. `thinking_level` and `system_prompt_template_id` have
  /// three-way semantics on the backend (absent = unchanged, null = reset /
  /// clear), so they are only sent when the corresponding `set*` flag is on.
  Future<Style> updateStyle(
    String styleId, {
    String? name,
    String? modelId,
    ThinkingLevel? thinkingLevel,
    bool setThinkingLevel = false,
    String? systemPromptTemplateId,
    bool setTemplateId = false,
    bool? isDefault,
  }) async {
    final response = await _api.patch(
      '/api/v1/styles/$styleId',
      data: {
        'name': ?name,
        'model_id': ?modelId,
        'is_default': ?isDefault,
        if (setThinkingLevel) 'thinking_level': thinkingLevel?.name,
        if (setTemplateId) 'system_prompt_template_id': systemPromptTemplateId,
      },
    );
    if (response.statusCode == 200) {
      return Style.fromJson(response.data as Map<String, dynamic>);
    }
    throw Exception('Failed to update style (${response.statusCode})');
  }

  Future<void> deleteStyle(String styleId) async {
    final response = await _api.delete('/api/v1/styles/$styleId');
    if (response.statusCode != 204) {
      throw Exception('Failed to delete style (${response.statusCode})');
    }
  }
}
