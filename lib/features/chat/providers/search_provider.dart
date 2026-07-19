import 'package:flutter/material.dart';
import 'package:garbanzo_ai/features/chat/models/search_result.dart';
import 'package:garbanzo_ai/features/chat/services/search_service.dart';

class SearchProvider extends ChangeNotifier {
  SearchProvider({SearchService? service})
    : _searchService = service ?? SearchService.instance;

  final SearchService _searchService;

  String _searchQuery = '';
  SearchResults? _results;
  bool _isLoading = false;
  String? _error;
  int _currentPage = 1;

  String get searchQuery => _searchQuery;
  SearchResults? get results => _results;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get currentPage => _currentPage;

  bool get hasResults => _results != null && _results!.items.isNotEmpty;
  bool get hasMore => _results?.hasMore ?? false;
  int get totalResults => _results?.total ?? 0;

  Future<void> search(String query, {int page = 1}) async {
    _searchQuery = query;
    _currentPage = page;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _results = await _searchService.searchConversations(
        query: query,
        page: page,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> nextPage() async {
    if (!hasMore) return;
    await search(_searchQuery, page: _currentPage + 1);
  }

  Future<void> previousPage() async {
    if (_currentPage <= 1) return;
    await search(_searchQuery, page: _currentPage - 1);
  }

  void clearSearch() {
    _searchQuery = '';
    _results = null;
    _currentPage = 1;
    _error = null;
    notifyListeners();
  }
}
