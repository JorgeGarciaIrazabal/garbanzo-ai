/// A user-defined prompt that runs on a schedule.
///
/// Exactly one of [cronExpr] or [runAt] is set. When the action fires the
/// backend creates a new conversation seeded with [prompt] and notifies the
/// user via the `reminders` channel.
class ScheduledAction {
  const ScheduledAction({
    required this.id,
    required this.userId,
    required this.prompt,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.cronExpr,
    this.runAt,
    this.model,
    this.systemPrompt,
    this.nextRun,
    this.lastRunAt,
    this.lastRunStatus,
  });

  final String id;
  final String userId;
  final String? title;
  final String prompt;
  final String? cronExpr;
  final DateTime? runAt;
  final String? model;
  final String? systemPrompt;
  final bool isActive;
  final DateTime? nextRun;
  final DateTime? lastRunAt;
  final String? lastRunStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRecurring => (cronExpr ?? '').isNotEmpty;

  factory ScheduledAction.fromJson(Map<String, dynamic> json) {
    DateTime? parseTs(Object? value) =>
        value == null ? null : DateTime.parse(value as String);

    return ScheduledAction(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String?,
      prompt: json['prompt'] as String,
      cronExpr: json['cron_expr'] as String?,
      runAt: parseTs(json['run_at']),
      model: json['model'] as String?,
      systemPrompt: json['system_prompt'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      nextRun: parseTs(json['next_run']),
      lastRunAt: parseTs(json['last_run_at']),
      lastRunStatus: json['last_run_status'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
