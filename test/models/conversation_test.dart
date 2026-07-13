import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';

void main() {
  group('Conversation', () {
    final sampleJson = {
      'id': 'conv-1',
      'title': 'Test Conversation',
      'model': 'llama3.2',
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T01:00:00.000Z',
      'message_count': 5,
    };

    test('fromJson parses correctly', () {
      final conv = Conversation.fromJson(sampleJson);
      expect(conv.id, 'conv-1');
      expect(conv.title, 'Test Conversation');
      expect(conv.model, 'llama3.2');
      expect(conv.messageCount, 5);
      expect(conv.createdAt, DateTime.utc(2024, 1, 1));
      expect(conv.updatedAt, DateTime.utc(2024, 1, 1, 1));
    });

    group('displayTitle', () {
      test('returns title when present', () {
        final conv = Conversation.fromJson(sampleJson);
        expect(conv.displayTitle, 'Test Conversation');
      });

      test('returns "New Conversation" when no title and no messages', () {
        final conv = Conversation.fromJson({
          ...sampleJson,
          'title': null,
          'messages': null,
        });
        expect(conv.displayTitle, 'New Conversation');
      });

      test('returns first user message content when no title', () {
        final conv = Conversation.fromJson({
          ...sampleJson,
          'title': null,
          'messages': [
            {
              'id': 'msg-1',
              'role': 'user',
              'content': 'Short question',
              'created_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        });
        expect(conv.displayTitle, 'Short question');
      });

      test('truncates long first message', () {
        final longContent = 'A' * 60;
        final conv = Conversation.fromJson({
          ...sampleJson,
          'title': null,
          'messages': [
            {
              'id': 'msg-1',
              'role': 'user',
              'content': longContent,
              'created_at': '2024-01-01T00:00:00.000Z',
            },
          ],
        });
        expect(conv.displayTitle, '${longContent.substring(0, 50)}...');
      });

      test('returns empty string title as "New Conversation"', () {
        final conv = Conversation.fromJson({
          ...sampleJson,
          'title': '',
        });
        expect(conv.displayTitle, 'New Conversation');
      });
    });
  });

  group('ConversationList', () {
    test('fromJson parses correctly', () {
      final json = {
        'items': [
          {
            'id': 'c1',
            'title': 'Conv 1',
            'model': 'llama3.2',
            'created_at': '2024-01-01T00:00:00.000Z',
            'updated_at': '2024-01-01T00:00:00.000Z',
            'message_count': 3,
          }
        ],
        'total': 10,
        'page': 1,
        'page_size': 20,
      };
      final list = ConversationList.fromJson(json);
      expect(list.items.length, 1);
      expect(list.total, 10);
      expect(list.page, 1);
      expect(list.pageSize, 20);
    });

    test('hasMore is true when more pages exist', () {
      final list = ConversationList(
        items: [],
        total: 30,
        page: 1,
        pageSize: 20,
      );
      expect(list.hasMore, true);
    });

    test('hasMore is false when all items shown', () {
      final list = ConversationList(
        items: [],
        total: 15,
        page: 1,
        pageSize: 20,
      );
      expect(list.hasMore, false);
    });

    test('totalPages calculation', () {
      final list = ConversationList(
        items: [],
        total: 45,
        page: 1,
        pageSize: 20,
      );
      expect(list.totalPages, 3);
    });
  });
}
