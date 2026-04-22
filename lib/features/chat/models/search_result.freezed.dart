// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'search_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

MatchedMessage _$MatchedMessageFromJson(Map<String, dynamic> json) {
  return _MatchedMessage.fromJson(json);
}

/// @nodoc
mixin _$MatchedMessage {
  String get id => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  String get role => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Context snippet showing match location (e.g., 50 chars before/after)
  String? get snippet => throw _privateConstructorUsedError;

  /// Serializes this MatchedMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MatchedMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MatchedMessageCopyWith<MatchedMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MatchedMessageCopyWith<$Res> {
  factory $MatchedMessageCopyWith(
    MatchedMessage value,
    $Res Function(MatchedMessage) then,
  ) = _$MatchedMessageCopyWithImpl<$Res, MatchedMessage>;
  @useResult
  $Res call({
    String id,
    String content,
    String role,
    DateTime createdAt,
    String? snippet,
  });
}

/// @nodoc
class _$MatchedMessageCopyWithImpl<$Res, $Val extends MatchedMessage>
    implements $MatchedMessageCopyWith<$Res> {
  _$MatchedMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MatchedMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? role = null,
    Object? createdAt = null,
    Object? snippet = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            role: null == role
                ? _value.role
                : role // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            snippet: freezed == snippet
                ? _value.snippet
                : snippet // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MatchedMessageImplCopyWith<$Res>
    implements $MatchedMessageCopyWith<$Res> {
  factory _$$MatchedMessageImplCopyWith(
    _$MatchedMessageImpl value,
    $Res Function(_$MatchedMessageImpl) then,
  ) = __$$MatchedMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String content,
    String role,
    DateTime createdAt,
    String? snippet,
  });
}

/// @nodoc
class __$$MatchedMessageImplCopyWithImpl<$Res>
    extends _$MatchedMessageCopyWithImpl<$Res, _$MatchedMessageImpl>
    implements _$$MatchedMessageImplCopyWith<$Res> {
  __$$MatchedMessageImplCopyWithImpl(
    _$MatchedMessageImpl _value,
    $Res Function(_$MatchedMessageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MatchedMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? content = null,
    Object? role = null,
    Object? createdAt = null,
    Object? snippet = freezed,
  }) {
    return _then(
      _$MatchedMessageImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        role: null == role
            ? _value.role
            : role // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        snippet: freezed == snippet
            ? _value.snippet
            : snippet // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$MatchedMessageImpl extends _MatchedMessage {
  const _$MatchedMessageImpl({
    required this.id,
    required this.content,
    required this.role,
    required this.createdAt,
    this.snippet,
  }) : super._();

  factory _$MatchedMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$MatchedMessageImplFromJson(json);

  @override
  final String id;
  @override
  final String content;
  @override
  final String role;
  @override
  final DateTime createdAt;

  /// Context snippet showing match location (e.g., 50 chars before/after)
  @override
  final String? snippet;

  @override
  String toString() {
    return 'MatchedMessage(id: $id, content: $content, role: $role, createdAt: $createdAt, snippet: $snippet)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MatchedMessageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.snippet, snippet) || other.snippet == snippet));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, content, role, createdAt, snippet);

  /// Create a copy of MatchedMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MatchedMessageImplCopyWith<_$MatchedMessageImpl> get copyWith =>
      __$$MatchedMessageImplCopyWithImpl<_$MatchedMessageImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$MatchedMessageImplToJson(this);
  }
}

abstract class _MatchedMessage extends MatchedMessage {
  const factory _MatchedMessage({
    required final String id,
    required final String content,
    required final String role,
    required final DateTime createdAt,
    final String? snippet,
  }) = _$MatchedMessageImpl;
  const _MatchedMessage._() : super._();

  factory _MatchedMessage.fromJson(Map<String, dynamic> json) =
      _$MatchedMessageImpl.fromJson;

  @override
  String get id;
  @override
  String get content;
  @override
  String get role;
  @override
  DateTime get createdAt;

  /// Context snippet showing match location (e.g., 50 chars before/after)
  @override
  String? get snippet;

  /// Create a copy of MatchedMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MatchedMessageImplCopyWith<_$MatchedMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ConversationSearchResult _$ConversationSearchResultFromJson(
  Map<String, dynamic> json,
) {
  return _ConversationSearchResult.fromJson(json);
}

/// @nodoc
mixin _$ConversationSearchResult {
  Conversation get conversation => throw _privateConstructorUsedError;
  List<MatchedMessage> get matchedMessages =>
      throw _privateConstructorUsedError;

  /// Serializes this ConversationSearchResult to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ConversationSearchResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ConversationSearchResultCopyWith<ConversationSearchResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConversationSearchResultCopyWith<$Res> {
  factory $ConversationSearchResultCopyWith(
    ConversationSearchResult value,
    $Res Function(ConversationSearchResult) then,
  ) = _$ConversationSearchResultCopyWithImpl<$Res, ConversationSearchResult>;
  @useResult
  $Res call({Conversation conversation, List<MatchedMessage> matchedMessages});

  $ConversationCopyWith<$Res> get conversation;
}

/// @nodoc
class _$ConversationSearchResultCopyWithImpl<
  $Res,
  $Val extends ConversationSearchResult
>
    implements $ConversationSearchResultCopyWith<$Res> {
  _$ConversationSearchResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ConversationSearchResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? conversation = null, Object? matchedMessages = null}) {
    return _then(
      _value.copyWith(
            conversation: null == conversation
                ? _value.conversation
                : conversation // ignore: cast_nullable_to_non_nullable
                      as Conversation,
            matchedMessages: null == matchedMessages
                ? _value.matchedMessages
                : matchedMessages // ignore: cast_nullable_to_non_nullable
                      as List<MatchedMessage>,
          )
          as $Val,
    );
  }

  /// Create a copy of ConversationSearchResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ConversationCopyWith<$Res> get conversation {
    return $ConversationCopyWith<$Res>(_value.conversation, (value) {
      return _then(_value.copyWith(conversation: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ConversationSearchResultImplCopyWith<$Res>
    implements $ConversationSearchResultCopyWith<$Res> {
  factory _$$ConversationSearchResultImplCopyWith(
    _$ConversationSearchResultImpl value,
    $Res Function(_$ConversationSearchResultImpl) then,
  ) = __$$ConversationSearchResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({Conversation conversation, List<MatchedMessage> matchedMessages});

  @override
  $ConversationCopyWith<$Res> get conversation;
}

/// @nodoc
class __$$ConversationSearchResultImplCopyWithImpl<$Res>
    extends
        _$ConversationSearchResultCopyWithImpl<
          $Res,
          _$ConversationSearchResultImpl
        >
    implements _$$ConversationSearchResultImplCopyWith<$Res> {
  __$$ConversationSearchResultImplCopyWithImpl(
    _$ConversationSearchResultImpl _value,
    $Res Function(_$ConversationSearchResultImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ConversationSearchResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? conversation = null, Object? matchedMessages = null}) {
    return _then(
      _$ConversationSearchResultImpl(
        conversation: null == conversation
            ? _value.conversation
            : conversation // ignore: cast_nullable_to_non_nullable
                  as Conversation,
        matchedMessages: null == matchedMessages
            ? _value._matchedMessages
            : matchedMessages // ignore: cast_nullable_to_non_nullable
                  as List<MatchedMessage>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ConversationSearchResultImpl extends _ConversationSearchResult {
  const _$ConversationSearchResultImpl({
    required this.conversation,
    final List<MatchedMessage> matchedMessages = const [],
  }) : _matchedMessages = matchedMessages,
       super._();

  factory _$ConversationSearchResultImpl.fromJson(Map<String, dynamic> json) =>
      _$$ConversationSearchResultImplFromJson(json);

  @override
  final Conversation conversation;
  final List<MatchedMessage> _matchedMessages;
  @override
  @JsonKey()
  List<MatchedMessage> get matchedMessages {
    if (_matchedMessages is EqualUnmodifiableListView) return _matchedMessages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_matchedMessages);
  }

  @override
  String toString() {
    return 'ConversationSearchResult(conversation: $conversation, matchedMessages: $matchedMessages)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConversationSearchResultImpl &&
            (identical(other.conversation, conversation) ||
                other.conversation == conversation) &&
            const DeepCollectionEquality().equals(
              other._matchedMessages,
              _matchedMessages,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    conversation,
    const DeepCollectionEquality().hash(_matchedMessages),
  );

  /// Create a copy of ConversationSearchResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ConversationSearchResultImplCopyWith<_$ConversationSearchResultImpl>
  get copyWith =>
      __$$ConversationSearchResultImplCopyWithImpl<
        _$ConversationSearchResultImpl
      >(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ConversationSearchResultImplToJson(this);
  }
}

abstract class _ConversationSearchResult extends ConversationSearchResult {
  const factory _ConversationSearchResult({
    required final Conversation conversation,
    final List<MatchedMessage> matchedMessages,
  }) = _$ConversationSearchResultImpl;
  const _ConversationSearchResult._() : super._();

  factory _ConversationSearchResult.fromJson(Map<String, dynamic> json) =
      _$ConversationSearchResultImpl.fromJson;

  @override
  Conversation get conversation;
  @override
  List<MatchedMessage> get matchedMessages;

  /// Create a copy of ConversationSearchResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ConversationSearchResultImplCopyWith<_$ConversationSearchResultImpl>
  get copyWith => throw _privateConstructorUsedError;
}

SearchResults _$SearchResultsFromJson(Map<String, dynamic> json) {
  return _SearchResults.fromJson(json);
}

/// @nodoc
mixin _$SearchResults {
  List<ConversationSearchResult> get items =>
      throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;
  int get page => throw _privateConstructorUsedError;
  @JsonKey(name: 'page_size')
  int get pageSize => throw _privateConstructorUsedError;
  String get query => throw _privateConstructorUsedError;

  /// Serializes this SearchResults to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SearchResults
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SearchResultsCopyWith<SearchResults> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SearchResultsCopyWith<$Res> {
  factory $SearchResultsCopyWith(
    SearchResults value,
    $Res Function(SearchResults) then,
  ) = _$SearchResultsCopyWithImpl<$Res, SearchResults>;
  @useResult
  $Res call({
    List<ConversationSearchResult> items,
    int total,
    int page,
    @JsonKey(name: 'page_size') int pageSize,
    String query,
  });
}

/// @nodoc
class _$SearchResultsCopyWithImpl<$Res, $Val extends SearchResults>
    implements $SearchResultsCopyWith<$Res> {
  _$SearchResultsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SearchResults
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? items = null,
    Object? total = null,
    Object? page = null,
    Object? pageSize = null,
    Object? query = null,
  }) {
    return _then(
      _value.copyWith(
            items: null == items
                ? _value.items
                : items // ignore: cast_nullable_to_non_nullable
                      as List<ConversationSearchResult>,
            total: null == total
                ? _value.total
                : total // ignore: cast_nullable_to_non_nullable
                      as int,
            page: null == page
                ? _value.page
                : page // ignore: cast_nullable_to_non_nullable
                      as int,
            pageSize: null == pageSize
                ? _value.pageSize
                : pageSize // ignore: cast_nullable_to_non_nullable
                      as int,
            query: null == query
                ? _value.query
                : query // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SearchResultsImplCopyWith<$Res>
    implements $SearchResultsCopyWith<$Res> {
  factory _$$SearchResultsImplCopyWith(
    _$SearchResultsImpl value,
    $Res Function(_$SearchResultsImpl) then,
  ) = __$$SearchResultsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<ConversationSearchResult> items,
    int total,
    int page,
    @JsonKey(name: 'page_size') int pageSize,
    String query,
  });
}

/// @nodoc
class __$$SearchResultsImplCopyWithImpl<$Res>
    extends _$SearchResultsCopyWithImpl<$Res, _$SearchResultsImpl>
    implements _$$SearchResultsImplCopyWith<$Res> {
  __$$SearchResultsImplCopyWithImpl(
    _$SearchResultsImpl _value,
    $Res Function(_$SearchResultsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SearchResults
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? items = null,
    Object? total = null,
    Object? page = null,
    Object? pageSize = null,
    Object? query = null,
  }) {
    return _then(
      _$SearchResultsImpl(
        items: null == items
            ? _value._items
            : items // ignore: cast_nullable_to_non_nullable
                  as List<ConversationSearchResult>,
        total: null == total
            ? _value.total
            : total // ignore: cast_nullable_to_non_nullable
                  as int,
        page: null == page
            ? _value.page
            : page // ignore: cast_nullable_to_non_nullable
                  as int,
        pageSize: null == pageSize
            ? _value.pageSize
            : pageSize // ignore: cast_nullable_to_non_nullable
                  as int,
        query: null == query
            ? _value.query
            : query // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SearchResultsImpl extends _SearchResults {
  const _$SearchResultsImpl({
    required final List<ConversationSearchResult> items,
    required this.total,
    required this.page,
    @JsonKey(name: 'page_size') required this.pageSize,
    required this.query,
  }) : _items = items,
       super._();

  factory _$SearchResultsImpl.fromJson(Map<String, dynamic> json) =>
      _$$SearchResultsImplFromJson(json);

  final List<ConversationSearchResult> _items;
  @override
  List<ConversationSearchResult> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final int total;
  @override
  final int page;
  @override
  @JsonKey(name: 'page_size')
  final int pageSize;
  @override
  final String query;

  @override
  String toString() {
    return 'SearchResults(items: $items, total: $total, page: $page, pageSize: $pageSize, query: $query)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SearchResultsImpl &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.page, page) || other.page == page) &&
            (identical(other.pageSize, pageSize) ||
                other.pageSize == pageSize) &&
            (identical(other.query, query) || other.query == query));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_items),
    total,
    page,
    pageSize,
    query,
  );

  /// Create a copy of SearchResults
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SearchResultsImplCopyWith<_$SearchResultsImpl> get copyWith =>
      __$$SearchResultsImplCopyWithImpl<_$SearchResultsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SearchResultsImplToJson(this);
  }
}

abstract class _SearchResults extends SearchResults {
  const factory _SearchResults({
    required final List<ConversationSearchResult> items,
    required final int total,
    required final int page,
    @JsonKey(name: 'page_size') required final int pageSize,
    required final String query,
  }) = _$SearchResultsImpl;
  const _SearchResults._() : super._();

  factory _SearchResults.fromJson(Map<String, dynamic> json) =
      _$SearchResultsImpl.fromJson;

  @override
  List<ConversationSearchResult> get items;
  @override
  int get total;
  @override
  int get page;
  @override
  @JsonKey(name: 'page_size')
  int get pageSize;
  @override
  String get query;

  /// Create a copy of SearchResults
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SearchResultsImplCopyWith<_$SearchResultsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
