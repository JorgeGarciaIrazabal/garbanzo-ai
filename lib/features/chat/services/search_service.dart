import 'package:garbanzo_ai/core/api_client.dart';
import 'package:garbanzo_ai/features/chat/models/search_result.dart';

class SearchService {
  SearchService._();

  static final instance = SearchService._();

  final _api = ApiClient.instance;

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

    try {
      final response = await _api.get(
        '/api/v1/chat/conversations/search',
        queryParameters: {'q': query, 'page': page, 'page_size': pageSize},
      );

      return SearchResults.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }
}
