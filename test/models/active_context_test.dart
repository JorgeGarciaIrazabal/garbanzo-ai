import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/topics/models/active_context.dart';

void main() {
  group('ActiveContext.fromJson', () {
    test('separates pinned and dynamic source items while retaining version', () {
      final context = ActiveContext.fromJson({
        'conversation_id': 'primary',
        'context_version': 7,
        'readiness': 'ready',
        'topic_is_pinned': true,
        'next_turn_summary': 'Current goal plus two supported sources.',
        'token_count': 450,
        'token_budget': 1200,
        'live_delta_count': 2,
        'items': [
          {
            'id': 'memory-1',
            'source_type': 'memory',
            'source_id': 'm-1',
            'state': 'pinned',
            'reason': 'Pinned by you',
          },
          {
            'id': 'message-1',
            'source_type': 'message',
            'source_id': 'msg-1',
            'state': 'dynamic',
            'reason': 'Relevant recent evidence',
          },
          {
            'id': 'message-2',
            'source_type': 'message',
            'source_id': 'msg-2',
            'state': 'excluded',
            'reason': 'Removed by user',
          },
        ],
      });

      expect(context.version, 7);
      expect(context.topicPinned, isTrue);
      expect(context.readiness, ActiveContextReadiness.ready);
      expect(context.pinnedItems.map((item) => item.id), ['memory-1']);
      expect(context.dynamicItems.map((item) => item.id), ['message-1']);
      expect(context.liveDeltaCount, 2);
    });

    test('uses limited readiness as a safe fallback', () {
      final context = ActiveContext.fromJson({
        'conversation_id': 'primary',
        'limited': true,
      });

      expect(context.readiness, ActiveContextReadiness.limited);
      expect(context.items, isEmpty);
      expect(context.version, 0);
    });

    test('parses the active-context endpoint grouping and nested status', () {
      final context = ActiveContext.fromJson({
        'conversation_id': 'primary',
        'context_version': 9,
        'status': {'readiness': 'preparing'},
        'pinned_items': [
          {
            'id': 'memory-1',
            'source_type': 'memory',
            'source_id': 'm-1',
            'state': 'pinned',
            'reason': 'Pinned by you',
          },
        ],
        'dynamic_items': [
          {
            'id': 'message-1',
            'source_type': 'message',
            'source_id': 'msg-1',
            'state': 'dynamic',
            'reason': 'Relevant evidence',
          },
        ],
        'excluded_items': [
          {
            'id': 'message-2',
            'source_type': 'message',
            'source_id': 'msg-2',
            'state': 'excluded',
            'reason': 'Removed by user',
          },
        ],
      });

      expect(context.readiness, ActiveContextReadiness.preparing);
      expect(context.pinnedItems, hasLength(1));
      expect(context.dynamicItems, hasLength(1));
      expect(context.items, hasLength(3));
    });
  });
}
