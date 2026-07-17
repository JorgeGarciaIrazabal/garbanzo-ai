import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/scheduled_actions/models/scheduled_action.dart';

/// HTTP client for the `/api/v1/scheduled-actions` endpoints.
class ScheduledActionsApiService {
  ScheduledActionsApiService._();
  static final ScheduledActionsApiService instance =
      ScheduledActionsApiService._();

  final ApiClient _api = ApiClient.instance;

  Future<List<ScheduledAction>> list() async {
    final response = await _api.get('/api/v1/scheduled-actions');
    if (response.statusCode == 200) {
      final data = response.data as List;
      return data
          .map((e) => ScheduledAction.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw _error(response);
  }

  Future<ScheduledAction> create({
    required String prompt,
    String? title,
    String? cronExpr,
    DateTime? runAt,
    String? model,
    String? systemPrompt,
    bool isActive = true,
  }) async {
    final response = await _api.post(
      '/api/v1/scheduled-actions',
      data: {
        'title': ?title,
        'prompt': prompt,
        'cron_expr': ?cronExpr,
        'run_at': ?runAt?.toUtc().toIso8601String(),
        'model': ?model,
        'system_prompt': ?systemPrompt,
        'is_active': isActive,
      },
    );
    if (response.statusCode == 201) {
      return ScheduledAction.fromJson(response.data as Map<String, dynamic>);
    }
    throw _error(response);
  }

  /// With [setSchedule] both `cron_expr` and `run_at` are sent explicitly
  /// (one null, one set) — the backend clears the null one, which is how an
  /// edit switches between recurring and one-off. Otherwise nulls are omitted.
  Future<ScheduledAction> update(
    String id, {
    String? title,
    String? prompt,
    String? cronExpr,
    DateTime? runAt,
    String? model,
    String? systemPrompt,
    bool? isActive,
    bool setSchedule = false,
  }) async {
    final response = await _api.patch(
      '/api/v1/scheduled-actions/$id',
      data: {
        'title': ?title,
        'prompt': ?prompt,
        if (setSchedule) ...{
          'cron_expr': cronExpr,
          'run_at': runAt?.toUtc().toIso8601String(),
        } else ...{
          'cron_expr': ?cronExpr,
          'run_at': ?runAt?.toUtc().toIso8601String(),
        },
        'model': ?model,
        'system_prompt': ?systemPrompt,
        'is_active': ?isActive,
      },
    );
    if (response.statusCode == 200) {
      return ScheduledAction.fromJson(response.data as Map<String, dynamic>);
    }
    throw _error(response);
  }

  Future<void> delete(String id) async {
    final response = await _api.delete('/api/v1/scheduled-actions/$id');
    if (response.statusCode != 204) {
      throw _error(response);
    }
  }

  Exception _error(dynamic response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail'] as String? ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    }
    return Exception('API Error (${response.statusCode}): $body');
  }
}
