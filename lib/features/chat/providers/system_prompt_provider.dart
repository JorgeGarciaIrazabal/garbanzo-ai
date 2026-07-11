import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/chat/models/system_prompt_template.dart';
import 'package:garbanzo_ai/features/chat/services/system_prompt_service.dart';

/// Manages the list of system prompt templates (builtins + user-saved) and
/// the user's global default system prompt.
class SystemPromptProvider extends ChangeNotifier with GuardedStateMixin {
  SystemPromptProvider() {
    refresh();
  }

  final SystemPromptService _service = SystemPromptService.instance;

  List<SystemPromptTemplate> _templates = [];
  List<SystemPromptTemplate> get templates => List.unmodifiable(_templates);

  String? _userDefault;
  String? get userDefault => _userDefault;

  List<SystemPromptTemplate> get builtinTemplates =>
      _templates.where((t) => t.isBuiltin).toList();

  List<SystemPromptTemplate> get customTemplates =>
      _templates.where((t) => !t.isBuiltin).toList();

  Future<void> refresh() async {
    await runGuarded('Failed to load system prompts', () async {
      final results = await Future.wait<Object?>([
        _service.listTemplates(),
        _service.getUserDefault(),
      ]);
      _templates = results[0] as List<SystemPromptTemplate>;
      _userDefault = results[1] as String?;
    });
  }

  Future<SystemPromptTemplate?> createTemplate({
    required String name,
    required String content,
    String? description,
  }) async {
    return runGuarded('Failed to create template', () async {
      final created = await _service.createTemplate(
        name: name,
        content: content,
        description: description,
      );
      _templates = [..._templates, created];
      return created;
    }, trackLoading: false);
  }

  Future<SystemPromptTemplate?> updateTemplate(
    String templateId, {
    String? name,
    String? content,
    String? description,
  }) async {
    return runGuarded('Failed to update template', () async {
      final updated = await _service.updateTemplate(
        templateId,
        name: name,
        content: content,
        description: description,
      );
      _templates = _templates
          .map((t) => t.id == updated.id ? updated : t)
          .toList();
      return updated;
    }, trackLoading: false);
  }

  Future<bool> deleteTemplate(String templateId) async {
    final ok = await runGuarded('Failed to delete template', () async {
      await _service.deleteTemplate(templateId);
      _templates = _templates.where((t) => t.id != templateId).toList();
      return true;
    }, trackLoading: false);
    return ok ?? false;
  }

  Future<void> setUserDefault(String? prompt) async {
    await runGuarded('Failed to save default prompt', () async {
      final trimmed = prompt?.trim();
      _userDefault = await _service.setUserDefault(
        trimmed == null || trimmed.isEmpty ? null : trimmed,
      );
    }, trackLoading: false);
  }
}
