import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/core/guarded_state.dart';
import 'package:garbanzo_ai/features/usage/models/usage_summary.dart';
import 'package:garbanzo_ai/features/usage/services/usage_service.dart';

class UsageProvider extends ChangeNotifier with GuardedStateMixin {
  final UsageService _service = UsageService.instance;

  UsageSummary? _summary;
  UsageSummary? get summary => _summary;

  int _days = 30;
  int get days => _days;

  Future<void> load({int? days}) async {
    if (days != null) _days = days;
    await runGuarded('Failed to load usage', () async {
      _summary = await _service.fetchSummary(days: _days);
    });
  }
}
