import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/chat/models/style.dart';
import 'package:garbanzo_ai/features/chat/models/thinking_level.dart';

/// Client for the `/api/v1/styles` endpoints.
class StyleService {
  StyleService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final StyleService instance = StyleService();

  /// For tests only: lets a fake subclass exist outside this library.
  @visibleForTesting
  StyleService.forTesting() : this();

  final ApiClient _api;

  Future<List<Style>> listStyles() async {
    final response = await _api.get('/api/v1/styles');
    expectStatus(response, const {200}, operation: 'Failed to list styles');
    final data = response.data as List<dynamic>;
    return data.map((e) => Style.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Style> createStyle({
    required String name,
    required String modelId,
    ThinkingLevel? thinkingLevel,
    String? systemPromptTemplateId,
    String? systemPromptContent,
    bool isDefault = false,
  }) async {
    final response = await _api.post(
      '/api/v1/styles',
      data: {
        'name': name,
        'model_id': modelId,
        'thinking_level': ?thinkingLevel?.name,
        'system_prompt_template_id': ?systemPromptTemplateId,
        'system_prompt_content': ?systemPromptContent,
        'is_default': isDefault,
      },
    );
    expectStatus(response, const {201}, operation: 'Failed to create style');
    return Style.fromJson(response.data as Map<String, dynamic>);
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
    String? systemPromptContent,
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
        'system_prompt_content': ?systemPromptContent,
      },
    );
    expectStatus(response, const {200}, operation: 'Failed to update style');
    return Style.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteStyle(String styleId) async {
    final response = await _api.delete('/api/v1/styles/$styleId');
    expectStatus(response, const {204}, operation: 'Failed to delete style');
  }
}
