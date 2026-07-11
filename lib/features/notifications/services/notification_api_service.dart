import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/notifications/models/app_notification.dart';

class NotificationListResult {
  const NotificationListResult({required this.items, required this.unreadCount});

  final List<AppNotification> items;
  final int unreadCount;
}

/// Service for the in-app notification center and user preferences.
class NotificationApiService {
  NotificationApiService._();
  static final NotificationApiService instance = NotificationApiService._();

  final ApiClient _api = ApiClient.instance;

  Future<NotificationListResult> list() async {
    final response = await _api.get('/api/v1/notifications');
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      final raw = (data['items'] as List? ?? []);
      final items = raw
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
      return NotificationListResult(
        items: items,
        unreadCount: data['unread_count'] as int? ?? 0,
      );
    }
    throw _handleError(response);
  }

  Future<int> unreadCount() async {
    final response = await _api.get('/api/v1/notifications/unread-count');
    if (response.statusCode == 200) {
      final data = response.data as Map<String, dynamic>;
      return data['unread_count'] as int? ?? 0;
    }
    throw _handleError(response);
  }

  Future<void> markRead(String id) async {
    final response = await _api.patch('/api/v1/notifications/$id/read');
    if (response.statusCode != 204) throw _handleError(response);
  }

  Future<void> markAllRead() async {
    final response = await _api.post('/api/v1/notifications/read-all');
    if (response.statusCode != 204) throw _handleError(response);
  }

  Future<void> delete(String id) async {
    final response = await _api.delete('/api/v1/notifications/$id');
    if (response.statusCode != 204) throw _handleError(response);
  }

  Future<NotificationPreferences> getPreferences() async {
    final response = await _api.get('/api/v1/notifications/preferences');
    if (response.statusCode == 200) {
      return NotificationPreferences.fromJson(
        response.data as Map<String, dynamic>,
      );
    }
    throw _handleError(response);
  }

  Future<NotificationPreferences> updatePreferences({
    bool? chatResponsesEnabled,
    bool? remindersEnabled,
    bool? systemAlertsEnabled,
  }) async {
    final payload = <String, dynamic>{};
    if (chatResponsesEnabled != null) {
      payload['chat_responses_enabled'] = chatResponsesEnabled;
    }
    if (remindersEnabled != null) {
      payload['reminders_enabled'] = remindersEnabled;
    }
    if (systemAlertsEnabled != null) {
      payload['system_alerts_enabled'] = systemAlertsEnabled;
    }
    final response = await _api.patch(
      '/api/v1/notifications/preferences',
      data: payload,
    );
    if (response.statusCode == 200) {
      return NotificationPreferences.fromJson(
        response.data as Map<String, dynamic>,
      );
    }
    throw _handleError(response);
  }

  Exception _handleError(dynamic response) {
    final body = response.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail'] as String? ?? 'Unknown error';
      return Exception('API Error (${response.statusCode}): $detail');
    }
    return Exception('API Error (${response.statusCode}): $body');
  }
}
