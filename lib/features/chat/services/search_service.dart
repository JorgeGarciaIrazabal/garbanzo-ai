import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/core/api_error.dart';
import 'package:garbanzo_ai/features/chat/models/search_result.dart';

class SearchService {
  SearchService({ApiClient? api}) : _api = api ?? ApiClient.instance;

  static final SearchService instance = SearchService();

  final ApiClient _api;

  Future<SearchResults> searchConversations({
    required String query,
    int page = 1,
    int pageSize = 20,
  }) async {
    if (query.trim().isEmpty) {
      return SearchResults(
        items: [],
        total: 0,
        page: page,
        pageSize: pageSize,
        query: query,
      );
    }

    final response = await _api.get(
      '/api/v1/chat/conversations/search',
      queryParameters: {'q': query, 'page': page, 'page_size': pageSize},
    );
    expectStatus(response, const {
      200,
    }, operation: 'Conversation search failed');
    return SearchResults.fromJson(response.data as Map<String, dynamic>);
  }
}
