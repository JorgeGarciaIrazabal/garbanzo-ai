import 'package:flutter/foundation.dart';

import '../../../core/auth_service.dart';
import '../models/model_info.dart';
import '../services/chat_service.dart';

/// Provider for managing LLM model selection.
///
/// Separated from [ChatProvider] so that model state can be loaded once
/// and shared across the app without tying it to a single conversation.
/// The user's default model is persisted on the backend via `/auth/me`.
class ModelProvider extends ChangeNotifier {
  ModelProvider() {
    _loadModels();
  }

  final ChatService _chatService = ChatService.instance;

  List<ModelInfo> _availableModels = [];
  List<ModelInfo> get availableModels => List.unmodifiable(_availableModels);

  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  Future<void> _loadModels() async {
    try {
      final modelList = await _chatService.listModels();
      _availableModels = modelList.models;

      if (_selectedModelId == null && _availableModels.isNotEmpty) {
        final serverDefault = AuthService.instance.cachedUser?.defaultModel;
        ModelInfo? match;
        if (serverDefault != null && serverDefault.isNotEmpty) {
          match = _availableModels.firstWhere(
            (m) => m.id == serverDefault,
            orElse: () => _pickFallback(_availableModels),
          );
        } else {
          match = _pickFallback(_availableModels);
        }
        _selectedModelId = match.id;
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to load models: $e');
      }
    }
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
