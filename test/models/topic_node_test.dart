import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/topics/models/topic_node.dart';
import 'package:garbanzo_ai/features/topics/widgets/topic_button.dart';

void main() {
  group('TopicNode.fromJson', () {
    test('parses an evidence-backed personal topic and nested child', () {
      final topic = TopicNode.fromJson({
        'id': 'retirement',
        'label': 'Retirement planning',
        'origin': 'personal',
        'score': 0.84,
        'signal': 'active now',
        'child_count': 1,
        'can_start': true,
        'context_status': {'state': 'ready'},
        'updated_at': '2026-08-30T12:34:56Z',
        'children': [
          {
            'id': 'contributions',
            'parent_id': 'retirement',
            'label': '401(k) contributions',
            'origin': 'personal',
            'score': 0.72,
            'context_status': 'preparing',
          },
        ],
      });

      expect(topic.origin, TopicOrigin.personal);
      expect(topic.contextStatus, TopicContextStatus.ready);
      expect(topic.score, 0.84);
      expect(topic.children, hasLength(1));
      expect(topic.children.single.parentId, 'retirement');
      expect(topic.children.single.contextStatus, TopicContextStatus.preparing);
      expect(topic.updatedAt, DateTime.utc(2026, 8, 30, 12, 34, 56));
    });

    test('falls back safely for unknown enum values and missing optional data', () {
      final topic = TopicNode.fromJson({
        'id': 'new-topic',
        'label': 'Something new',
        'origin': 'unrecognized-source',
        'context_status': 'unknown',
      });

      expect(topic.origin, TopicOrigin.history);
      expect(topic.contextStatus, TopicContextStatus.empty);
      expect(topic.childCount, 0);
      expect(topic.children, isEmpty);
      expect(topic.canStart, isTrue);
    });

    test('preserves public history and suggested origins for discovery routing', () {
      final learned = TopicNode.fromJson({
        'id': 'learned',
        'label': 'Learned from history',
        'origin': 'history',
      });
      final explore = TopicNode.fromJson({
        'id': 'explore',
        'label': 'Something new',
        'origin': 'suggested',
      });

      expect(learned.origin, TopicOrigin.history);
      expect(explore.origin, TopicOrigin.suggested);
    });

    test('serializes and deserializes combinedTopics', () {
      final node = TopicNode.fromJson({
        'id': 'family',
        'label': 'Family',
        'origin': 'personal',
        'combined_topics': ['Retirement', 'Real Estate'],
      });

      expect(node.combinedTopics, ['Retirement', 'Real Estate']);
      expect(node.toJson()['combined_topics'], ['Retirement', 'Real Estate']);

      final copied = node.copyWith(combinedTopics: ['Retirement']);
      expect(copied.combinedTopics, ['Retirement']);
    });
  });

  group('shortenTopicTitle', () {
    test('preserves short and concise topic titles', () {
      expect(shortenTopicTitle('Finance', isMobile: true), 'Finance');
      expect(shortenTopicTitle('Cooking Pasta', isMobile: true), 'Cooking Pasta');
      expect(shortenTopicTitle('Machine Learning', isMobile: true), 'Machine Learning');
      expect(shortenTopicTitle('Travel someday', isMobile: true), 'Travel someday');
    });

    test('preserves full title when isMobile is false', () {
      const longTitle = 'Review Intermediation Contract – Madrid Property Sale';
      expect(shortenTopicTitle(longTitle, isMobile: false), longTitle);
    });

    test('extracts concise clause from delimited titles', () {
      expect(
        shortenTopicTitle('Review Intermediation Contract – Madrid Property Sale', isMobile: true),
        'Madrid Property Sale',
      );
      expect(
        shortenTopicTitle('Deep Dive - Neural Architecture', isMobile: true),
        'Neural Architecture',
      );
    });

    test('strips verbose suffixes when exceeding maxChars', () {
      expect(
        shortenTopicTitle('Guadarrama & Aranjuez Property Search', isMobile: true),
        'Guadarrama & Aranjuez',
      );
      expect(
        shortenTopicTitle('Asset-Backed Mortgage for Home Purchase', isMobile: true),
        'Asset-Backed Mortgage',
      );
      expect(
        shortenTopicTitle('Local Inference Hardware Benchmarks', isMobile: true),
        'Local Inference',
      );
    });
  });
}
