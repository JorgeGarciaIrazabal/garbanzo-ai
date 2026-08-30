import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/chat/models/model_info.dart';
import 'package:garbanzo_ai/features/chat/services/chat_service.dart';

enum VisionModelChoiceKind { faster, smarter, compatible }

class VisionModelChoice {
  const VisionModelChoice({required this.model, required this.kind});

  final ModelInfo model;
  final VisionModelChoiceKind kind;
}

/// Provider for managing LLM model selection.
///
/// Separated from [ChatProvider] so that model state can be loaded once
/// and shared across the app without tying it to a single conversation.
/// The user's default model is persisted on the backend via `/auth/me`.
class ModelProvider extends ChangeNotifier with GuardedStateMixin {
  static const fastVisionModelId = 'glm-5.3-flash:cloud';
  static const smartVisionModelId = 'kimi-k3:cloud';

  ModelProvider({ChatService? chatService, AuthService? authService})
    : _chatService = chatService ?? ChatService.instance,
      _authService = authService ?? AuthService.instance {
    _loadModels();
  }

  final ChatService _chatService;
  final AuthService _authService;

  List<ModelInfo> _availableModels = [];
  List<ModelInfo> get availableModels => List.unmodifiable(_availableModels);

  String? _serverDefaultModelId;

  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  Future<void> _loadModels() async {
    await runGuarded('Failed to load models', () async {
      final modelList = await _chatService.listModels();
      _availableModels = modelList.models;
      _serverDefaultModelId = modelList.defaultModel;

      if (_selectedModelId == null && _availableModels.isNotEmpty) {
        // Preference order: the user's persisted default (via /auth/me) >
        // the models endpoint's server-recommended default > the hardcoded
        // fallback chain (used only if neither hint is present/valid).
        final userDefault = _authService.cachedUser?.defaultModel;
        final serverDefault = modelList.defaultModel;
        ModelInfo? match;
        for (final candidate in [userDefault, serverDefault]) {
          if (candidate != null && candidate.isNotEmpty) {
            match = _availableModels
                .where((m) => m.id == candidate)
                .firstOrNull;
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
    final result = await _authService.updateProfile(defaultModel: modelId);
    return result.success;
  }

  /// Pick a sensible default when no server-side preference exists. Prefer
  /// the latest qwen3.8 reasoning model, falling back to the older qwen3
  /// family, then llama3.2, then whatever's first.
  static ModelInfo _pickFallback(List<ModelInfo> models) {
    for (final pattern in <String>['qwen3.8', 'qwen3:', 'llama3.2']) {
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

  /// Preferred choices for recovering from an image sent to a text-only
  /// model. Only return models that the server currently exposes: a choice in
  /// this list is safe for the UI to switch to immediately.
  ///
  /// GLM 5.3 Flash is the fast/lower-cost path and Kimi K3 is the
  /// smarter/higher-cost path. If neither preferred cloud model is enabled,
  /// retain the general capability-aware recommendation as a fallback.
  List<VisionModelChoice> visionModelChoices({
    String? currentModelId,
    bool preferThinking = false,
  }) {
    final choices = <VisionModelChoice>[];

    void addPreferred(String id, VisionModelChoiceKind kind) {
      final model = _availableModels
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (model?.supportsVision == true) {
        choices.add(VisionModelChoice(model: model!, kind: kind));
      }
    }

    addPreferred(fastVisionModelId, VisionModelChoiceKind.faster);
    addPreferred(smartVisionModelId, VisionModelChoiceKind.smarter);
    if (choices.isNotEmpty) return choices;

    final fallback = recommendedVisionModel(
      currentModelId: currentModelId,
      preferThinking: preferThinking,
    );
    return fallback == null
        ? const []
        : [
            VisionModelChoice(
              model: fallback,
              kind: VisionModelChoiceKind.compatible,
            ),
          ];
  }

  /// Best available model for an image-bearing turn. Stay on the same
  /// local/cloud side when possible so suggesting a model never quietly
  /// changes where the user's attachment is processed. Within that pool,
  /// preserve tool/thinking support when possible, then prefer the server
  /// default and a larger context window.
  ModelInfo? recommendedVisionModel({
    String? currentModelId,
    bool preferThinking = false,
  }) {
    final candidates = _availableModels
        .where((model) => model.supportsVision == true)
        .toList();
    if (candidates.isEmpty) return null;

    final currentIsCloud = currentModelId?.endsWith(':cloud');
    final sameLocation = currentIsCloud == null
        ? <ModelInfo>[]
        : candidates
              .where((model) => model.id.endsWith(':cloud') == currentIsCloud)
              .toList();
    var pool = sameLocation.isEmpty ? candidates : sameLocation;

    final toolCapable = pool
        .where((model) => model.supportsTools == true)
        .toList();
    if (toolCapable.isNotEmpty) pool = toolCapable;
    if (preferThinking) {
      final thinkingCapable = pool
          .where((model) => model.supportsThinking == true)
          .toList();
      if (thinkingCapable.isNotEmpty) pool = thinkingCapable;
    }

    int score(ModelInfo model) {
      var value = 0;
      if (model.id == _serverDefaultModelId) value += 1000;
      value += (model.contextLength ?? 0) ~/ 10000;
      return value;
    }

    pool.sort((a, b) => score(b).compareTo(score(a)));
    return pool.first;
  }
}
