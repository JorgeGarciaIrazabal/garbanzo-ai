import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

/// Provider for managing LLM model selection.
///
/// Separated from [ChatProvider] so that model state can be loaded once
/// and shared across the app without tying it to a single conversation.
/// The user's default model is persisted on the backend via `/auth/me`.
class ModelProvider extends ChangeNotifier with GuardedStateMixin {
  ModelProvider() {
    _loadModels();
  }

  final ChatService _chatService = ChatService.instance;

  List<ModelInfo> _availableModels = [];
  List<ModelInfo> get availableModels => List.unmodifiable(_availableModels);

  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  Future<void> _loadModels() async {
    await runGuarded('Failed to load models', () async {
      final modelList = await _chatService.listModels();
      _availableModels = modelList.models;

      if (_selectedModelId == null && _availableModels.isNotEmpty) {
        // Preference order: the user's persisted default (via /auth/me) >
        // the models endpoint's server-recommended default > the hardcoded
        // fallback chain (used only if neither hint is present/valid).
        final userDefault = AuthService.instance.cachedUser?.defaultModel;
        final serverDefault = modelList.defaultModel;
        ModelInfo? match;
        for (final candidate in [userDefault, serverDefault]) {
          if (candidate != null && candidate.isNotEmpty) {
            match = _availableModels.where((m) => m.id == candidate).firstOrNull;
            if (match != null) break;
          }
        }
        match ??= _pickFallback(_availableModels);
        _selectedModelId = match.id;
      }
    }, trackLoading: false);
  }

  void selectModel(String modelId) {
    if (_availableModels.any((m) => m.id == modelId)) {
      _selectedModelId = modelId;
      notifyListeners();
    }
  }

  /// Persist [modelId] as the user's default. Use `null` to clear.
  Future<bool> setDefaultModel(String? modelId) async {
    final result = await AuthService.instance.updateProfile(
      defaultModel: modelId,
    );
    return result.success;
  }

  /// Pick a sensible default when no server-side preference exists. Prefer
  /// the latest qwen3.6 reasoning model, falling back to the older qwen3
  /// family, then llama3.2, then whatever's first.
  static ModelInfo _pickFallback(List<ModelInfo> models) {
    for (final pattern in <String>['qwen3.6', 'qwen3:', 'llama3.2']) {
      final hit = models.where((m) => m.id.contains(pattern)).firstOrNull;
      if (hit != null) return hit;
    }
    return models.first;
  }

  ModelInfo? get selectedModel {
    if (_selectedModelId == null) return null;
    return _availableModels.firstWhere(
      (m) => m.id == _selectedModelId,
      orElse: () => _availableModels.first,
    );
  }

  Future<void> refreshModels() async => _loadModels();
}
