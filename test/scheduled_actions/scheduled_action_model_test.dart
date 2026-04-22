import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/scheduled_actions/models/scheduled_action.dart';

void main() {
  group('ScheduledAction.fromJson', () {
    Map<String, dynamic> base() => {
          'id': 'a1',
          'user_id': 'u@example.com',
          'prompt': 'Hi',
          'is_active': true,
          'created_at': '2026-04-21T00:00:00.000Z',
          'updated_at': '2026-04-21T01:00:00.000Z',
        };

    test('parses a minimal recurring action', () {
      final action = ScheduledAction.fromJson({
        ...base(),
        'cron_expr': '0 9 * * *',
      });
      expect(action.id, 'a1');
      expect(action.cronExpr, '0 9 * * *');
      expect(action.runAt, isNull);
      expect(action.isRecurring, isTrue);
      expect(action.isActive, isTrue);
    });

    test('parses a one-off action with run_at', () {
      final action = ScheduledAction.fromJson({
        ...base(),
        'run_at': '2026-05-01T09:00:00.000Z',
      });
      expect(action.runAt, DateTime.utc(2026, 5, 1, 9));
      expect(action.cronExpr, isNull);
      expect(action.isRecurring, isFalse);
    });

    test('parses optional metadata fields', () {
      final action = ScheduledAction.fromJson({
        ...base(),
        'cron_expr': '* * * * *',
        'title': 'Standup',
        'model': 'llama3.2',
        'system_prompt': 'Be concise.',
        'next_run': '2026-04-22T09:00:00.000Z',
        'last_run_at': '2026-04-21T09:00:00.000Z',
        'last_run_status': 'success',
      });
      expect(action.title, 'Standup');
      expect(action.model, 'llama3.2');
      expect(action.systemPrompt, 'Be concise.');
      expect(action.nextRun, DateTime.utc(2026, 4, 22, 9));
      expect(action.lastRunAt, DateTime.utc(2026, 4, 21, 9));
      expect(action.lastRunStatus, 'success');
    });

    test('treats null cron_expr as non-recurring', () {
      final action = ScheduledAction.fromJson({
        ...base(),
        'cron_expr': null,
        'run_at': '2026-05-01T09:00:00.000Z',
      });
      expect(action.isRecurring, isFalse);
    });

    test('treats empty cron_expr as non-recurring', () {
      final action = ScheduledAction.fromJson({
        ...base(),
        'cron_expr': '',
        'run_at': '2026-05-01T09:00:00.000Z',
      });
      expect(action.isRecurring, isFalse);
    });
  });
}
