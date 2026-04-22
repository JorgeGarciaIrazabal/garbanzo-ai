import 'package:freezed_annotation/freezed_annotation.dart';

import 'conversation.dart';

part 'search_result.freezed.dart';
part 'search_result.g.dart';

/// A message that matched the search query.
@freezed
class MatchedMessage with _$MatchedMessage {
  const MatchedMessage._();

  const factory MatchedMessage({
    required String id,
    required String content,
    required String role,
    required DateTime createdAt,
    /// Context snippet showing match location (e.g., 50 chars before/after)
    String? snippet,
  }) = _MatchedMessage;

  factory MatchedMessage.fromJson(Map<String, dynamic> json) =>
      _$MatchedMessageFromJson(json);
}

/// Search result with conversation and matched messages.
@freezed
class ConversationSearchResult with _$ConversationSearchResult {
  const ConversationSearchResult._();

  const factory ConversationSearchResult({
    required Conversation conversation,
    @Default([]) List<MatchedMessage> matchedMessages,
  }) = _ConversationSearchResult;

  factory ConversationSearchResult.fromJson(Map<String, dynamic> json) =>
      _$ConversationSearchResultFromJson(json);
}

/// Paginated search results.
@freezed
class SearchResults with _$SearchResults {
  const SearchResults._();

  const factory SearchResults({
    required List<ConversationSearchResult> items,
    required int total,
    required int page,
    @JsonKey(name: 'page_size') required int pageSize,
    required String query,
  }) = _SearchResults;

  factory SearchResults.fromJson(Map<String, dynamic> json) =>
      _$SearchResultsFromJson(json);

  bool get hasMore => total > page * pageSize;
  int get totalPages => (total / pageSize).ceil();
}

