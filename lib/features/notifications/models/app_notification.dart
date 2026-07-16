/// An in-app notification shown in the notification center.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.data,
  });

  final String id;
  final String channel;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      channel: channel,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      data: data,
    );
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      channel: json['channel'] as String? ?? 'chat_responses',
      title: json['title'] as String,
      body: json['body'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}

class NotificationPreferences {
  const NotificationPreferences({
    required this.chatResponsesEnabled,
    required this.remindersEnabled,
    required this.systemAlertsEnabled,
    required this.friendUpdatesEnabled,
  });

  final bool chatResponsesEnabled;
  final bool remindersEnabled;
  final bool systemAlertsEnabled;
  final bool friendUpdatesEnabled;

  NotificationPreferences copyWith({
    bool? chatResponsesEnabled,
    bool? remindersEnabled,
    bool? systemAlertsEnabled,
    bool? friendUpdatesEnabled,
  }) {
    return NotificationPreferences(
      chatResponsesEnabled: chatResponsesEnabled ?? this.chatResponsesEnabled,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      systemAlertsEnabled: systemAlertsEnabled ?? this.systemAlertsEnabled,
      friendUpdatesEnabled: friendUpdatesEnabled ?? this.friendUpdatesEnabled,
    );
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      chatResponsesEnabled: json['chat_responses_enabled'] as bool? ?? true,
      remindersEnabled: json['reminders_enabled'] as bool? ?? true,
      systemAlertsEnabled: json['system_alerts_enabled'] as bool? ?? true,
      friendUpdatesEnabled: json['friend_updates_enabled'] as bool? ?? true,
    );
  }
}
