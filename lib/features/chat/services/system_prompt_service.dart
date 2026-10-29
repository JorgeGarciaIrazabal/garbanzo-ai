import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// Client for the `/api/v1/system-prompts` endpoints.
class SystemPromptService {
  SystemPromptService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  /// Allows focused tests to supply prompt transport without a singleton.
  @visibleForTesting
  SystemPromptService.forTesting() : this();
  static final SystemPromptService instance = SystemPromptService();

  final ApiClient _api;

  Future<List<SystemPromptTemplate>> listTemplates({String? locale}) async {
    final response = await _api.get(
      '/api/v1/system-prompts/templates',
      queryParameters: {'locale': locale},
    );
    expectStatus(response, const {200}, operation: 'Failed to list templates');
    final data = response.data as List<dynamic>;
    return data
        .map((e) => SystemPromptTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Resolve a style reference independently of the visible picker locale.
  /// No reference is legitimate; a required reference must exist or fail.
  Future<SystemPromptTemplate?> resolveTemplate(
    String? templateId, {
    Iterable<SystemPromptTemplate> cachedTemplates = const [],
  }) async {
    if (templateId == null) return null;
    final cached = cachedTemplates.where((t) => t.id == templateId).firstOrNull;
    if (cached != null) return cached;
    final templates = await listTemplates();
    final template = templates.where((t) => t.id == templateId).firstOrNull;
    if (template == null) throw StateError('Style prompt template not found');
    return template;
  }

  Future<SystemPromptTemplate> createTemplate({
    required String name,
    required String content,
    String? description,
  }) async {
    final response = await _api.post(
      '/api/v1/system-prompts/templates',
      data: {'name': name, 'content': content, 'description': ?description},
    );
    expectStatus(response, const {201}, operation: 'Failed to create template');
    return SystemPromptTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SystemPromptTemplate> updateTemplate(
    String templateId, {
    String? name,
    String? content,
    String? description,
  }) async {
    final response = await _api.patch(
      '/api/v1/system-prompts/templates/$templateId',
      data: {'name': ?name, 'content': ?content, 'description': ?description},
    );
    expectStatus(response, const {200}, operation: 'Failed to update template');
    return SystemPromptTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteTemplate(String templateId) async {
    final response = await _api.delete(
      '/api/v1/system-prompts/templates/$templateId',
    );
    expectStatus(response, const {204}, operation: 'Failed to delete template');
  }

  Future<String?> getUserDefault() async {
    final response = await _api.get('/api/v1/system-prompts/user-default');
    expectStatus(response, const {
      200,
    }, operation: 'Failed to load user default');
    final data = response.data as Map<String, dynamic>;
    return data['default_system_prompt'] as String?;
  }

  Future<String?> setUserDefault(String? prompt) async {
    final response = await _api.put(
      '/api/v1/system-prompts/user-default',
      data: {'default_system_prompt': prompt},
    );
    expectStatus(response, const {
      200,
    }, operation: 'Failed to save user default');
    final data = response.data as Map<String, dynamic>;
    return data['default_system_prompt'] as String?;
  }

  /// Stream an AI-generated system prompt via SSE.
  ///
  /// [intent] is the natural-language description. When [existingPrompt] and
  /// [feedback] are provided, the LLM refines the draft instead of generating
  /// from scratch. [model] optionally overrides the LLM model.
  Stream<ChatResponseChunk> generate({
    required String intent,
    String? existingPrompt,
    String? feedback,
    String? model,
  }) async* {
    final response = await _api.streamPost(
      '/api/v1/system-prompts/generate',
      data: {
        'intent': intent,
        'existing_prompt': ?existingPrompt,
        'feedback': ?feedback,
        'model': ?model,
      },
    );

    final byteStream = (response.data as ResponseBody).stream;

    if (response.statusCode != 200) {
      final errorBody = await byteStream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      String? detail;
      try {
        detail = apiErrorDetail(jsonDecode(errorBody)) ?? errorBody;
      } catch (_) {
        detail = errorBody;
      }
      throw ApiResponseException(
        statusCode: response.statusCode ?? 0,
        operation: 'Generate failed',
        detail: detail,
      );
    }

    yield* parseSseChunks(byteStream.cast<List<int>>().transform(utf8.decoder));
  }
}
