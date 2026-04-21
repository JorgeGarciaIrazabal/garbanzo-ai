import 'package:flutter/foundation.dart';

import '../models/system_prompt_template.dart';
import '../services/system_prompt_service.dart';

/// Manages the list of system prompt templates (builtins + user-saved) and
/// the user's global default system prompt.
class SystemPromptProvider extends ChangeNotifier {
  SystemPromptProvider() {
    refresh();
  }

  final SystemPromptService _service = SystemPromptService.instance;

  List<SystemPromptTemplate> _templates = [];
  List<SystemPromptTemplate> get templates => List.unmodifiable(_templates);

  String? _userDefault;
  String? get userDefault => _userDefault;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<SystemPromptTemplate> get builtinTemplates =>
      _templates.where((t) => t.isBuiltin).toList();

  List<SystemPromptTemplate> get customTemplates =>
      _templates.where((t) => !t.isBuiltin).toList();

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        _service.listTemplates(),
        _service.getUserDefault(),
      ]);
      _templates = results[0] as List<SystemPromptTemplate>;
      _userDefault = results[1] as String?;
    } catch (e) {
      _error = 'Failed to load system prompts: $e';
      if (kDebugMode) print(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<SystemPromptTemplate?> createTemplate({
    required String name,
    required String content,
    String? description,
  }) async {
    try {
      final created = await _service.createTemplate(
        name: name,
        content: content,
        description: description,
      );
      _templates = [..._templates, created];
      notifyListeners();
      return created;
    } catch (e) {
      _error = 'Failed to create template: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
      return null;
    }
  }

  Future<SystemPromptTemplate?> updateTemplate(
    String templateId, {
    String? name,
    String? content,
    String? description,
  }) async {
    try {
      final updated = await _service.updateTemplate(
        templateId,
        name: name,
        content: content,
        description: description,
      );
      _templates = _templates
          .map((t) => t.id == updated.id ? updated : t)
          .toList();
      notifyListeners();
      return updated;
    } catch (e) {
      _error = 'Failed to update template: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteTemplate(String templateId) async {
    try {
      await _service.deleteTemplate(templateId);
      _templates = _templates.where((t) => t.id != templateId).toList();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete template: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
      return false;
    }
  }

  Future<void> setUserDefault(String? prompt) async {
    try {
      final trimmed = prompt?.trim();
      _userDefault = await _service.setUserDefault(
        trimmed == null || trimmed.isEmpty ? null : trimmed,
      );
      notifyListeners();
    } catch (e) {
      _error = 'Failed to save default prompt: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }
}
