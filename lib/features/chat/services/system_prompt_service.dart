import '../../../core/api_client.dart';
import '../models/system_prompt_template.dart';

/// Client for the `/api/v1/system-prompts` endpoints.
class SystemPromptService {
  SystemPromptService._();
  static final SystemPromptService instance = SystemPromptService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<SystemPromptTemplate>> listTemplates() async {
    final response = await _api.get('/api/v1/system-prompts/templates');
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
      data: {
        'name': name,
        'content': content,
        'description': ?description,
      },
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
      data: {
        'name': ?name,
        'content': ?content,
        'description': ?description,
      },
    );
    if (response.statusCode == 200) {
      return SystemPromptTemplate.fromJson(
        response.data as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to update template (${response.statusCode})');
  }

  Future<void> deleteTemplate(String templateId) async {
    final response =
        await _api.delete('/api/v1/system-prompts/templates/$templateId');
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
}
