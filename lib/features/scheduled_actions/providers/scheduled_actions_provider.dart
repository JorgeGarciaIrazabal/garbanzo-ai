import 'package:flutter/foundation.dart';

import '../models/scheduled_action.dart';
import '../services/scheduled_actions_api_service.dart';

/// State for the scheduled-actions page.
class ScheduledActionsProvider extends ChangeNotifier {
  ScheduledActionsProvider({ScheduledActionsApiService? service})
      : _api = service ?? ScheduledActionsApiService.instance;

  final ScheduledActionsApiService _api;

  List<ScheduledAction> _actions = [];
  List<ScheduledAction> get actions => List.unmodifiable(_actions);

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _actions = await _api.list();
    } catch (e) {
      _error = 'Failed to load scheduled actions: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<ScheduledAction?> create({
    required String prompt,
    String? title,
    String? cronExpr,
    DateTime? runAt,
    String? systemPrompt,
    String? model,
  }) async {
    try {
      final action = await _api.create(
        prompt: prompt,
        title: title,
        cronExpr: cronExpr,
        runAt: runAt,
        systemPrompt: systemPrompt,
        model: model,
      );
      _actions = [action, ..._actions];
      notifyListeners();
      return action;
    } catch (e) {
      _error = '$e';
      notifyListeners();
      return null;
    }
  }

  Future<void> setActive(String id, bool isActive) async {
    try {
      final updated = await _api.update(id, isActive: isActive);
      _replace(updated);
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    try {
      await _api.delete(id);
      _actions = _actions.where((a) => a.id != id).toList();
      notifyListeners();
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  void _replace(ScheduledAction updated) {
    final idx = _actions.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;
    _actions = [
      ..._actions.sublist(0, idx),
      updated,
      ..._actions.sublist(idx + 1),
    ];
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
