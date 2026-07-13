import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/memory/models/memory.dart';
import 'package:garbanzo_ai/features/memory/providers/memory_provider.dart';
import 'package:garbanzo_ai/features/memory/services/memory_api_service.dart';
import 'package:mocktail/mocktail.dart';

class MockMemoryApiService extends Mock implements MemoryApiService {}

Memory _memory(String id, {String content = 'a fact', bool isActive = true}) {
  return Memory(
    id: id,
    userId: 'test@example.com',
    content: content,
    createdAt: DateTime.utc(2026),
    isActive: isActive,
  );
}

void main() {
  late MockMemoryApiService service;

  setUp(() {
    service = MockMemoryApiService();
  });

  MemoryProvider provider() => MemoryProvider(service: service);

  group('loading', () {
    test('loads memories on construction', () async {
      when(() => service.listMemories())
          .thenAnswer((_) async => [_memory('m1'), _memory('m2')]);

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.memories.map((m) => m.id), ['m1', 'm2']);
      expect(p.error, isNull);
      expect(p.isLoading, isFalse);
    });

    test('surfaces a load failure as a user-facing error', () async {
      when(() => service.listMemories())
          .thenThrow(Exception('API Error (500): boom'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      expect(p.memories, isEmpty);
      expect(p.error, isNotNull);
    });

    test('refreshMemories replaces the list and clears a prior error',
        () async {
      when(() => service.listMemories())
          .thenThrow(Exception('API Error (500): boom'));
      final p = provider();
      await Future<void>.delayed(Duration.zero);
      expect(p.error, isNotNull);

      when(() => service.listMemories())
          .thenAnswer((_) async => [_memory('m1')]);
      await p.refreshMemories();

      expect(p.error, isNull);
      expect(p.memories.single.id, 'm1');
    });
  });

  group('createMemory', () {
    test('prepends the created memory and toggles isCreating', () async {
      when(() => service.listMemories()).thenAnswer((_) async => [_memory('old')]);
      when(
        () => service.createMemory(
          content: any(named: 'content'),
          sourceConversationId: any(named: 'sourceConversationId'),
        ),
      ).thenAnswer((_) async => _memory('new', content: 'fresh fact'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);

      final future = p.createMemory(content: 'fresh fact');
      expect(p.isCreating, isTrue);
      await future;

      expect(p.isCreating, isFalse);
      expect(p.memories.map((m) => m.id), ['new', 'old']);
    });

    test('keeps the list intact when creation fails', () async {
      when(() => service.listMemories()).thenAnswer((_) async => [_memory('old')]);
      when(
        () => service.createMemory(
          content: any(named: 'content'),
          sourceConversationId: any(named: 'sourceConversationId'),
        ),
      ).thenThrow(Exception('API Error (500): nope'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.createMemory(content: 'fresh fact');

      expect(p.error, isNotNull);
      expect(p.isCreating, isFalse);
      expect(p.memories.map((m) => m.id), ['old']);
    });
  });

  group('updateMemory', () {
    test('replaces the matching entry in place', () async {
      when(() => service.listMemories())
          .thenAnswer((_) async => [_memory('m1'), _memory('m2')]);
      when(
        () => service.updateMemory(
          memoryId: 'm2',
          content: any(named: 'content'),
          isActive: any(named: 'isActive'),
        ),
      ).thenAnswer((_) async => _memory('m2', content: 'updated'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.updateMemory(memoryId: 'm2', content: 'updated');

      expect(p.memories.map((m) => m.id), ['m1', 'm2']);
      expect(p.memories.last.content, 'updated');
      expect(p.isUpdating, isFalse);
    });

    test('toggleMemoryActive flips the flag through updateMemory', () async {
      when(() => service.listMemories())
          .thenAnswer((_) async => [_memory('m1', isActive: true)]);
      when(
        () => service.updateMemory(
          memoryId: 'm1',
          content: any(named: 'content'),
          isActive: false,
        ),
      ).thenAnswer((_) async => _memory('m1', isActive: false));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.toggleMemoryActive('m1', true);

      verify(
        () => service.updateMemory(
          memoryId: 'm1',
          content: any(named: 'content'),
          isActive: false,
        ),
      ).called(1);
      expect(p.memories.single.isActive, isFalse);
    });
  });

  group('deactivateMemory', () {
    test('removes the memory from the list', () async {
      when(() => service.listMemories())
          .thenAnswer((_) async => [_memory('m1'), _memory('m2')]);
      when(() => service.deactivateMemory('m1')).thenAnswer((_) async {});

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.deactivateMemory('m1');

      expect(p.memories.map((m) => m.id), ['m2']);
    });

    test('keeps the memory when the API call fails', () async {
      when(() => service.listMemories())
          .thenAnswer((_) async => [_memory('m1')]);
      when(() => service.deactivateMemory('m1'))
          .thenThrow(Exception('API Error (500): nope'));

      final p = provider();
      await Future<void>.delayed(Duration.zero);
      await p.deactivateMemory('m1');

      expect(p.memories.map((m) => m.id), ['m1']);
      expect(p.error, isNotNull);
    });
  });
}
