import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/memory/models/memory.dart';
import 'package:garbanzo_ai/features/memory/services/memory_api_service.dart';

/// Provider for managing memory state.
///
/// Handles loading, creating, updating, and deleting memories.
class MemoryProvider extends ChangeNotifier with GuardedStateMixin {
  MemoryProvider() {
    _loadMemories();
  }

  final MemoryApiService _memoryService = MemoryApiService.instance;

  // ==========================================================================
  // State
  // ==========================================================================

  List<Memory> _memories = [];
  List<Memory> get memories => List.unmodifiable(_memories);

  bool _isCreating = false;
  bool get isCreating => _isCreating;

  bool _isUpdating = false;
  bool get isUpdating => _isUpdating;

  // ==========================================================================
  // Memory operations
  // ==========================================================================

  Future<void> _loadMemories() async {
    await runGuarded('Failed to load memories', () async {
      _memories = await _memoryService.listMemories();
    });
  }

  Future<void> refreshMemories() async => _loadMemories();

  /// Create a new memory.
  Future<void> createMemory({
    required String content,
    String? sourceConversationId,
  }) async {
    _isCreating = true;
    notifyListeners();
    await runGuarded('Failed to create memory', () async {
      final memory = await _memoryService.createMemory(
        content: content,
        sourceConversationId: sourceConversationId,
      );
      _memories = [memory, ..._memories];
    }, trackLoading: false);
    _isCreating = false;
    notifyListeners();
  }

  /// Update a memory's content or active status.
  Future<void> updateMemory({
    required String memoryId,
    String? content,
    bool? isActive,
  }) async {
    _isUpdating = true;
    notifyListeners();
    await runGuarded('Failed to update memory', () async {
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
      }
    }, trackLoading: false);
    _isUpdating = false;
    notifyListeners();
  }

  /// Deactivate (soft-delete) a memory.
  Future<void> deactivateMemory(String memoryId) async {
    await runGuarded('Failed to deactivate memory', () async {
      await _memoryService.deactivateMemory(memoryId);
      _memories.removeWhere((m) => m.id == memoryId);
    }, trackLoading: false);
  }

  /// Toggle a memory's active status.
  Future<void> toggleMemoryActive(String memoryId, bool currentlyActive) async {
    await updateMemory(memoryId: memoryId, isActive: !currentlyActive);
  }
}
