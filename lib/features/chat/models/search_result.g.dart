// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MatchedMessage _$MatchedMessageFromJson(Map<String, dynamic> json) =>
    _MatchedMessage(
      id: json['id'] as String,
      content: json['content'] as String,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      snippet: json['snippet'] as String?,
    );

Map<String, dynamic> _$MatchedMessageToJson(_MatchedMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'content': instance.content,
      'role': instance.role,
      'created_at': instance.createdAt.toIso8601String(),
      'snippet': instance.snippet,
    };

_ConversationSearchResult _$ConversationSearchResultFromJson(
  Map<String, dynamic> json,
) => _ConversationSearchResult(
  conversation: Conversation.fromJson(
    json['conversation'] as Map<String, dynamic>,
  ),
  matchedMessages:
      (json['matched_messages'] as List<dynamic>?)
          ?.map((e) => MatchedMessage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$ConversationSearchResultToJson(
  _ConversationSearchResult instance,
) => <String, dynamic>{
  'conversation': instance.conversation,
  'matched_messages': instance.matchedMessages,
};

_SearchResults _$SearchResultsFromJson(Map<String, dynamic> json) =>
    _SearchResults(
      items: (json['items'] as List<dynamic>)
          .map(
            (e) => ConversationSearchResult.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      total: (json['total'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      pageSize: (json['page_size'] as num).toInt(),
      query: json['query'] as String,
    );

Map<String, dynamic> _$SearchResultsToJson(_SearchResults instance) =>
    <String, dynamic>{
      'items': instance.items,
      'total': instance.total,
      'page': instance.page,
      'page_size': instance.pageSize,
      'query': instance.query,
    };
