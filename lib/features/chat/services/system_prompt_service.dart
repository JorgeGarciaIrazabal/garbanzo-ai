import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// Client for the `/api/v1/system-prompts` endpoints.
class SystemPromptService {
  SystemPromptService._();
  static final SystemPromptService instance = SystemPromptService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<SystemPromptTemplate>> listTemplates({String? locale}) async {
    final response = await _api.get(
      '/api/v1/system-prompts/templates',
      queryParameters: {'locale': locale},
    );
    if (response.statusCode == 200) {
      final data = response.data as List<dynamic>;
      return data
          .map((e) => SystemPromptTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to list templates (${response.statusCode})');
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
    if (response.statusCode == 201) {
      return SystemPromptTemplate.fromJson(
        response.data as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to create template (${response.statusCode})');
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
    if (response.statusCode == 200) {
      return SystemPromptTemplate.fromJson(
        response.data as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to update template (${response.statusCode})');
  }

  Future<void> deleteTemplate(String templateId) async {
    final response = await _api.delete(
      '/api/v1/system-prompts/templates/$templateId',
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to delete template (${response.statusCode})');
    }
  }

  Future<String?> getUserDefault() async {
    final response = await _api.get('/api/v1/system-prompts/user-default');
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return data['default_system_prompt'] as String?;
    }
    throw Exception('Failed to load user default (${response.statusCode})');
  }

  Future<String?> setUserDefault(String? prompt) async {
    final response = await _api.put(
      '/api/v1/system-prompts/user-default',
      data: {'default_system_prompt': prompt},
    );
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return data['default_system_prompt'] as String?;
    }
    throw Exception('Failed to save user default (${response.statusCode})');
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
      throw Exception('Generate failed: ${response.statusCode} - $errorBody');
    }

    yield* parseSseChunks(byteStream.cast<List<int>>().transform(utf8.decoder));
  }
}
