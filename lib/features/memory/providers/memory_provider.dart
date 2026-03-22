import 'package:flutter/foundation.dart';

import '../models/memory.dart';
import '../services/memory_api_service.dart';

/// Provider for managing memory state.
///
/// Handles loading, creating, updating, and deleting memories.
class MemoryProvider extends ChangeNotifier {
  MemoryProvider() {
    _loadMemories();
  }

  final MemoryApiService _memoryService = MemoryApiService.instance;

  // ==========================================================================
  // State
  // ==========================================================================

  List<Memory> _memories = [];
  List<Memory> get memories => List.unmodifiable(_memories);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool _isCreating = false;
  bool get isCreating => _isCreating;

  bool _isUpdating = false;
  bool get isUpdating => _isUpdating;

  // ==========================================================================
  // Memory operations
  // ==========================================================================

  Future<void> _loadMemories() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final memories = await _memoryService.listMemories();
      _memories = memories;
    } catch (e) {
      _error = 'Failed to load memories: $e';
      if (kDebugMode) print(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshMemories() async => _loadMemories();

  /// Create a new memory.
  Future<void> createMemory({
    required String content,
    String? sourceConversationId,
  }) async {
    _isCreating = true;
    _error = null;
    notifyListeners();

    try {
      final memory = await _memoryService.createMemory(
        content: content,
        sourceConversationId: sourceConversationId,
      );
      _memories = [memory, ..._memories];
      notifyListeners();
    } catch (e) {
      _error = 'Failed to create memory: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    } finally {
      _isCreating = false;
    }
  }

  /// Update a memory's content or active status.
  Future<void> updateMemory({
    required String memoryId,
    String? content,
    bool? isActive,
  }) async {
    _isUpdating = true;
    _error = null;
    notifyListeners();

    try {
      final updated = await _memoryService.updateMemory(
        memoryId: memoryId,
        content: content,
        isActive: isActive,
      );
      final index = _memories.indexWhere((m) => m.id == memoryId);
      if (index >= 0) {
        _memories = [
          ..._memories.sublist(0, index),
          updated,
          ..._memories.sublist(index + 1),
        ];
        notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to update memory: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    } finally {
      _isUpdating = false;
    }
  }

  /// Deactivate (soft-delete) a memory.
  Future<void> deactivateMemory(String memoryId) async {
    _error = null;
    notifyListeners();

    try {
      await _memoryService.deactivateMemory(memoryId);
      _memories.removeWhere((m) => m.id == memoryId);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to deactivate memory: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  /// Toggle a memory's active status.
  Future<void> toggleMemoryActive(String memoryId, bool currentlyActive) async {
    await updateMemory(
      memoryId: memoryId,
      isActive: !currentlyActive,
    );
  }

  // ==========================================================================
  // Error handling
  // ==========================================================================

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
