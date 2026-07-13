import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    final sampleJson = {
      'id': 'msg-1',
      'role': 'user',
      'content': 'Hello!',
      'created_at': '2024-01-01T00:00:00.000Z',
      'meta': {'tokens': 5},
    };

    test('fromJson parses correctly', () {
      final msg = ChatMessage.fromJson(sampleJson);
      expect(msg.id, 'msg-1');
      expect(msg.role, 'user');
      expect(msg.content, 'Hello!');
      expect(msg.createdAt, DateTime.utc(2024, 1, 1));
      expect(msg.metadata, {'tokens': 5});
    });

    test('fromJson reads "meta" key for metadata', () {
      final json = {
        ...sampleJson,
        'meta': {'key': 'from_meta'},
      };
      json.remove('metadata');
      final msg = ChatMessage.fromJson(json);
      expect(msg.metadata?['key'], 'from_meta');
    });

    test('fromJson reads "metadata" key as fallback', () {
      final json = {
        'id': 'msg-2',
        'role': 'user',
        'content': 'hi',
        'created_at': '2024-01-01T00:00:00.000Z',
        'metadata': {'key': 'from_metadata'},
      };
      final msg = ChatMessage.fromJson(json);
      expect(msg.metadata?['key'], 'from_metadata');
    });

    test('isUser, isAssistant, isSystem', () {
      final user =
          ChatMessage.fromJson({...sampleJson, 'role': 'user'});
      expect(user.isUser, true);
      expect(user.isAssistant, false);
      expect(user.isSystem, false);

      final assistant =
          ChatMessage.fromJson({...sampleJson, 'role': 'assistant'});
      expect(assistant.isAssistant, true);

      final system =
          ChatMessage.fromJson({...sampleJson, 'role': 'system'});
      expect(system.isSystem, true);
    });
  });

  group('ChatResponseChunk', () {
    test('fromJson chunk type', () {
      final chunk = ChatResponseChunk.fromJson({
        'type': 'chunk',
        'content': 'hello',
      });
      expect(chunk.isChunk, true);
      expect(chunk.isDone, false);
      expect(chunk.isError, false);
      expect(chunk.isThinking, false);
      expect(chunk.content, 'hello');
    });

    test('fromJson done type with metadata', () {
      final chunk = ChatResponseChunk.fromJson({
        'type': 'done',
        'metadata': {'tokens': 42},
      });
      expect(chunk.isDone, true);
      expect(chunk.metadata?['tokens'], 42);
    });

    test('fromJson error type', () {
      final chunk = ChatResponseChunk.fromJson({
        'type': 'error',
        'error': 'something broke',
      });
      expect(chunk.isError, true);
      expect(chunk.error, 'something broke');
    });

    test('fromJson thinking type', () {
      final chunk = ChatResponseChunk.fromJson({
        'type': 'thinking',
        'content': 'let me think...',
      });
      expect(chunk.isThinking, true);
      expect(chunk.content, 'let me think...');
    });
  });
}
