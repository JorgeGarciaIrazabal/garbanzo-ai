import 'package:flutter_test/flutter_test.dart';
import 'package:garbanzo_ai/features/chat/models/conversation.dart';
import 'package:garbanzo_ai/features/chat/models/search_result.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/services/search_service.dart';
import 'package:mocktail/mocktail.dart';

class MockSearchService extends Mock implements SearchService {}

SearchResults _results({
  required String query,
  int page = 1,
  int pageSize = 20,
  int total = 0,
  int itemCount = 0,
}) {
  return SearchResults(
    items: List.generate(
      itemCount,
      (i) => ConversationSearchResult(
        conversation: Conversation(
          id: 'c$i',
          title: 'Conv $i',
          model: 'qwen3:8b',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ),
    ),
    total: total,
    page: page,
    pageSize: pageSize,
    query: query,
  );
}

void main() {
  late MockSearchService service;

  setUp(() {
    service = MockSearchService();
  });

  SearchProvider provider() => SearchProvider(service: service);

  void stub({int total = 0, int itemCount = 0, int pageSize = 20}) {
    when(
      () => service.searchConversations(
        query: any(named: 'query'),
        page: any(named: 'page'),
      ),
    ).thenAnswer(
      (inv) async => _results(
        query: inv.namedArguments[#query] as String,
        page: inv.namedArguments[#page] as int,
        pageSize: pageSize,
        total: total,
        itemCount: itemCount,
      ),
    );
  }

  group('search', () {
    test('stores results and derived getters on success', () async {
      stub(total: 30, itemCount: 20);
      final p = provider();

      await p.search('hello');

      expect(p.searchQuery, 'hello');
      expect(p.hasResults, isTrue);
      expect(p.totalResults, 30);
      expect(p.hasMore, isTrue); // 30 > 1 * 20
      expect(p.isLoading, isFalse);
      expect(p.error, isNull);
    });

    test('captures an error and clears loading on failure', () async {
      when(
        () => service.searchConversations(
          query: any(named: 'query'),
          page: any(named: 'page'),
        ),
      ).thenThrow(Exception('API Error (500): boom'));
      final p = provider();

      await p.search('hello');

      expect(p.error, isNotNull);
      expect(p.isLoading, isFalse);
      expect(p.hasResults, isFalse);
    });
  });

  group('pagination', () {
    test('nextPage advances the page when more results exist', () async {
      stub(total: 60, itemCount: 20);
      final p = provider();
      await p.search('hi');
      expect(p.currentPage, 1);

      await p.nextPage();

      expect(p.currentPage, 2);
      verify(() => service.searchConversations(query: 'hi', page: 2)).called(1);
    });

    test('nextPage is a no-op when there are no more results', () async {
      stub(total: 10, itemCount: 10);
      final p = provider();
      await p.search('hi');

      await p.nextPage();

      expect(p.currentPage, 1);
      verifyNever(() => service.searchConversations(query: 'hi', page: 2));
    });

    test('previousPage is a no-op on the first page', () async {
      stub(total: 60, itemCount: 20);
      final p = provider();
      await p.search('hi');

      await p.previousPage();

      expect(p.currentPage, 1);
    });

    test('previousPage steps back after advancing', () async {
      stub(total: 60, itemCount: 20);
      final p = provider();
      await p.search('hi');
      await p.nextPage();
      expect(p.currentPage, 2);

      await p.previousPage();

      expect(p.currentPage, 1);
    });
  });

  group('clearSearch', () {
    test('resets query, results, page, and error', () async {
      stub(total: 30, itemCount: 20);
      final p = provider();
      await p.search('hello');
      await p.nextPage();

      p.clearSearch();

      expect(p.searchQuery, '');
      expect(p.results, isNull);
      expect(p.currentPage, 1);
      expect(p.error, isNull);
      expect(p.hasResults, isFalse);
    });
  });
}
