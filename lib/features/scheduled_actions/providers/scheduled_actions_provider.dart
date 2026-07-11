import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/scheduled_actions/models/scheduled_action.dart';
import 'package:garbanzo_ai/features/scheduled_actions/services/scheduled_actions_api_service.dart';

/// State for the scheduled-actions page.
class ScheduledActionsProvider extends ChangeNotifier with GuardedStateMixin {
  ScheduledActionsProvider({ScheduledActionsApiService? service})
    : _api = service ?? ScheduledActionsApiService.instance;

  final ScheduledActionsApiService _api;

  List<ScheduledAction> _actions = [];
  List<ScheduledAction> get actions => List.unmodifiable(_actions);

  /// Forwards to [isLoading]; the page reads `.loading`.
  bool get loading => isLoading;

  Future<void> load() async {
    await runGuarded('Failed to load scheduled actions', () async {
      _actions = await _api.list();
    });
  }

  Future<ScheduledAction?> create({
    required String prompt,
    String? title,
    String? cronExpr,
    DateTime? runAt,
    String? systemPrompt,
    String? model,
  }) async {
    return runGuarded('Failed to create scheduled action', () async {
      final action = await _api.create(
        prompt: prompt,
        title: title,
        cronExpr: cronExpr,
        runAt: runAt,
        systemPrompt: systemPrompt,
        model: model,
      );
      _actions = [action, ..._actions];
      return action;
    }, trackLoading: false);
  }

  Future<void> setActive(String id, bool isActive) async {
    await runGuarded('Failed to update scheduled action', () async {
      final updated = await _api.update(id, isActive: isActive);
      _replace(updated);
    }, trackLoading: false);
  }

  Future<void> delete(String id) async {
    await runGuarded('Failed to delete scheduled action', () async {
      await _api.delete(id);
      _actions = _actions.where((a) => a.id != id).toList();
    }, trackLoading: false);
  }

  void _replace(ScheduledAction updated) {
    final idx = _actions.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;
    _actions = [
      ..._actions.sublist(0, idx),
      updated,
      ..._actions.sublist(idx + 1),
    ];
  }
}
