import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/usage/models/usage_summary.dart';

void main() {
  group('UsageSummary.fromJson', () {
    test('parses empty response with defaults', () {
      final summary = UsageSummary.fromJson({
        'days': 30,
        'total_tokens_prompt': 0,
        'total_tokens_generated': 0,
        'total_messages': 0,
        'by_model': <dynamic>[],
        'by_conversation': <dynamic>[],
        'by_day': <dynamic>[],
      });

      expect(summary.days, 30);
      expect(summary.totalTokens, 0);
      expect(summary.totalMessages, 0);
      expect(summary.byModel, isEmpty);
    });

    test('parses populated response', () {
      final summary = UsageSummary.fromJson({
        'days': 7,
        'total_tokens_prompt': 100,
        'total_tokens_generated': 200,
        'total_messages': 5,
        'by_model': [
          {
            'model': 'llama3.2',
            'tokens_prompt': 60,
            'tokens_generated': 120,
            'message_count': 3,
          },
        ],
        'by_conversation': [
          {
            'conversation_id': 'c1',
            'title': 'Chat',
            'tokens_prompt': 60,
            'tokens_generated': 120,
            'message_count': 3,
          },
        ],
        'by_day': [
          {
            'date': '2026-04-21',
            'tokens_prompt': 50,
            'tokens_generated': 100,
          },
        ],
      });

      expect(summary.totalTokens, 300);
      expect(summary.byModel.single.model, 'llama3.2');
      expect(summary.byModel.single.totalTokens, 180);
      expect(summary.byConversation.single.conversationId, 'c1');
      expect(summary.byDay.single.date.year, 2026);
      expect(summary.byDay.single.date.month, 4);
      expect(summary.byDay.single.date.day, 21);
    });

    test('gracefully handles missing keys', () {
      final summary = UsageSummary.fromJson(<String, dynamic>{});
      expect(summary.days, 30);
      expect(summary.totalTokens, 0);
      expect(summary.byModel, isEmpty);
    });
  });
}
