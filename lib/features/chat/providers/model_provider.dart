import 'package:flutter/foundation.dart';

import '../models/model_info.dart';
import '../services/chat_service.dart';

/// Provider for managing LLM model selection.
///
/// Separated from [ChatProvider] so that model state can be loaded once
/// and shared across the app without tying it to a single conversation.
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
        final preferred = _availableModels.firstWhere(
          (m) => m.id.contains('llama3.2'),
          orElse: () => _availableModels.first,
        );
        _selectedModelId = preferred.id;
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

  ModelInfo? get selectedModel {
    if (_selectedModelId == null) return null;
    return _availableModels.firstWhere(
      (m) => m.id == _selectedModelId,
      orElse: () => _availableModels.first,
    );
  }

  Future<void> refreshModels() async => _loadModels();
}
