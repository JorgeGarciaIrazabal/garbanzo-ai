import 'package:flutter/foundation.dart';

import '../models/usage_summary.dart';
import '../services/usage_service.dart';

class UsageProvider extends ChangeNotifier {
  final UsageService _service = UsageService.instance;

  UsageSummary? _summary;
  UsageSummary? get summary => _summary;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  int _days = 30;
  int get days => _days;

  Future<void> load({int? days}) async {
    if (days != null) _days = days;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _summary = await _service.fetchSummary(days: _days);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
