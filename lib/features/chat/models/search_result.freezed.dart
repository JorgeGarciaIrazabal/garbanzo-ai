// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'search_result.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MatchedMessage {

 String get id; String get content; String get role; DateTime get createdAt;/// Context snippet showing match location (e.g., 50 chars before/after)
 String? get snippet;
/// Create a copy of MatchedMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MatchedMessageCopyWith<MatchedMessage> get copyWith => _$MatchedMessageCopyWithImpl<MatchedMessage>(this as MatchedMessage, _$identity);

  /// Serializes this MatchedMessage to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MatchedMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.content, content) || other.content == content)&&(identical(other.role, role) || other.role == role)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.snippet, snippet) || other.snippet == snippet));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,content,role,createdAt,snippet);

@override
String toString() {
  return 'MatchedMessage(id: $id, content: $content, role: $role, createdAt: $createdAt, snippet: $snippet)';
}


}

/// @nodoc
abstract mixin class $MatchedMessageCopyWith<$Res>  {
  factory $MatchedMessageCopyWith(MatchedMessage value, $Res Function(MatchedMessage) _then) = _$MatchedMessageCopyWithImpl;
@useResult
$Res call({
 String id, String content, String role, DateTime createdAt, String? snippet
});




}
/// @nodoc
class _$MatchedMessageCopyWithImpl<$Res>
    implements $MatchedMessageCopyWith<$Res> {
  _$MatchedMessageCopyWithImpl(this._self, this._then);

  final MatchedMessage _self;
  final $Res Function(MatchedMessage) _then;

/// Create a copy of MatchedMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? content = null,Object? role = null,Object? createdAt = null,Object? snippet = freezed,}) {
  return _then(MatchedMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,snippet: freezed == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [MatchedMessage].
extension MatchedMessagePatterns on MatchedMessage {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MatchedMessage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MatchedMessage() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MatchedMessage value)  $default,){
final _that = this;
switch (_that) {
case _MatchedMessage():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MatchedMessage value)?  $default,){
final _that = this;
switch (_that) {
case _MatchedMessage() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String content,  String role,  DateTime createdAt,  String? snippet)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MatchedMessage() when $default != null:
return $default(_that.id,_that.content,_that.role,_that.createdAt,_that.snippet);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String content,  String role,  DateTime createdAt,  String? snippet)  $default,) {final _that = this;
switch (_that) {
case _MatchedMessage():
return $default(_that.id,_that.content,_that.role,_that.createdAt,_that.snippet);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String content,  String role,  DateTime createdAt,  String? snippet)?  $default,) {final _that = this;
switch (_that) {
case _MatchedMessage() when $default != null:
return $default(_that.id,_that.content,_that.role,_that.createdAt,_that.snippet);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MatchedMessage extends MatchedMessage {
  const _MatchedMessage({required this.id, required this.content, required this.role, required this.createdAt, this.snippet}): super._();
  factory _MatchedMessage.fromJson(Map<String, dynamic> json) => _$MatchedMessageFromJson(json);

@override final  String id;
@override final  String content;
@override final  String role;
@override final  DateTime createdAt;
/// Context snippet showing match location (e.g., 50 chars before/after)
@override final  String? snippet;

/// Create a copy of MatchedMessage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MatchedMessageCopyWith<_MatchedMessage> get copyWith => __$MatchedMessageCopyWithImpl<_MatchedMessage>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MatchedMessageToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MatchedMessage&&(identical(other.id, id) || other.id == id)&&(identical(other.content, content) || other.content == content)&&(identical(other.role, role) || other.role == role)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.snippet, snippet) || other.snippet == snippet));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,content,role,createdAt,snippet);

@override
String toString() {
  return 'MatchedMessage(id: $id, content: $content, role: $role, createdAt: $createdAt, snippet: $snippet)';
}


}

/// @nodoc
abstract mixin class _$MatchedMessageCopyWith<$Res> implements $MatchedMessageCopyWith<$Res> {
  factory _$MatchedMessageCopyWith(_MatchedMessage value, $Res Function(_MatchedMessage) _then) = __$MatchedMessageCopyWithImpl;
@override @useResult
$Res call({
 String id, String content, String role, DateTime createdAt, String? snippet
});




}
/// @nodoc
class __$MatchedMessageCopyWithImpl<$Res>
    implements _$MatchedMessageCopyWith<$Res> {
  __$MatchedMessageCopyWithImpl(this._self, this._then);

  final _MatchedMessage _self;
  final $Res Function(_MatchedMessage) _then;

/// Create a copy of MatchedMessage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? content = null,Object? role = null,Object? createdAt = null,Object? snippet = freezed,}) {
  return _then(_MatchedMessage(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,snippet: freezed == snippet ? _self.snippet : snippet // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$ConversationSearchResult {

 Conversation get conversation; List<MatchedMessage> get matchedMessages;
/// Create a copy of ConversationSearchResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationSearchResultCopyWith<ConversationSearchResult> get copyWith => _$ConversationSearchResultCopyWithImpl<ConversationSearchResult>(this as ConversationSearchResult, _$identity);

  /// Serializes this ConversationSearchResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationSearchResult&&(identical(other.conversation, conversation) || other.conversation == conversation)&&const DeepCollectionEquality().equals(other.matchedMessages, matchedMessages));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,conversation,const DeepCollectionEquality().hash(matchedMessages));

@override
String toString() {
  return 'ConversationSearchResult(conversation: $conversation, matchedMessages: $matchedMessages)';
}


}

/// @nodoc
abstract mixin class $ConversationSearchResultCopyWith<$Res>  {
  factory $ConversationSearchResultCopyWith(ConversationSearchResult value, $Res Function(ConversationSearchResult) _then) = _$ConversationSearchResultCopyWithImpl;
@useResult
$Res call({
 Conversation conversation, List<MatchedMessage> matchedMessages
});


$ConversationCopyWith<$Res> get conversation;

}
/// @nodoc
class _$ConversationSearchResultCopyWithImpl<$Res>
    implements $ConversationSearchResultCopyWith<$Res> {
  _$ConversationSearchResultCopyWithImpl(this._self, this._then);

  final ConversationSearchResult _self;
  final $Res Function(ConversationSearchResult) _then;

/// Create a copy of ConversationSearchResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? conversation = null,Object? matchedMessages = null,}) {
  return _then(ConversationSearchResult(
conversation: null == conversation ? _self.conversation : conversation // ignore: cast_nullable_to_non_nullable
as Conversation,matchedMessages: null == matchedMessages ? _self.matchedMessages : matchedMessages // ignore: cast_nullable_to_non_nullable
as List<MatchedMessage>,
  ));
}
/// Create a copy of ConversationSearchResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCopyWith<$Res> get conversation {
  
  return $ConversationCopyWith<$Res>(_self.conversation, (value) {
    return _then(_self.copyWith(conversation: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConversationSearchResult].
extension ConversationSearchResultPatterns on ConversationSearchResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationSearchResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationSearchResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationSearchResult value)  $default,){
final _that = this;
switch (_that) {
case _ConversationSearchResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationSearchResult value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationSearchResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Conversation conversation,  List<MatchedMessage> matchedMessages)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationSearchResult() when $default != null:
return $default(_that.conversation,_that.matchedMessages);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Conversation conversation,  List<MatchedMessage> matchedMessages)  $default,) {final _that = this;
switch (_that) {
case _ConversationSearchResult():
return $default(_that.conversation,_that.matchedMessages);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Conversation conversation,  List<MatchedMessage> matchedMessages)?  $default,) {final _that = this;
switch (_that) {
case _ConversationSearchResult() when $default != null:
return $default(_that.conversation,_that.matchedMessages);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationSearchResult extends ConversationSearchResult {
  const _ConversationSearchResult({required this.conversation,  List<MatchedMessage> matchedMessages = const []}): _matchedMessages = matchedMessages,super._();
  factory _ConversationSearchResult.fromJson(Map<String, dynamic> json) => _$ConversationSearchResultFromJson(json);

@override final  Conversation conversation;
 final  List<MatchedMessage> _matchedMessages;
@override@JsonKey() List<MatchedMessage> get matchedMessages {
  if (_matchedMessages is EqualUnmodifiableListView) return _matchedMessages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_matchedMessages);
}


/// Create a copy of ConversationSearchResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationSearchResultCopyWith<_ConversationSearchResult> get copyWith => __$ConversationSearchResultCopyWithImpl<_ConversationSearchResult>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationSearchResultToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationSearchResult&&(identical(other.conversation, conversation) || other.conversation == conversation)&&const DeepCollectionEquality().equals(other._matchedMessages, _matchedMessages));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,conversation,const DeepCollectionEquality().hash(_matchedMessages));

@override
String toString() {
  return 'ConversationSearchResult(conversation: $conversation, matchedMessages: $matchedMessages)';
}


}

/// @nodoc
abstract mixin class _$ConversationSearchResultCopyWith<$Res> implements $ConversationSearchResultCopyWith<$Res> {
  factory _$ConversationSearchResultCopyWith(_ConversationSearchResult value, $Res Function(_ConversationSearchResult) _then) = __$ConversationSearchResultCopyWithImpl;
@override @useResult
$Res call({
 Conversation conversation, List<MatchedMessage> matchedMessages
});


@override $ConversationCopyWith<$Res> get conversation;

}
/// @nodoc
class __$ConversationSearchResultCopyWithImpl<$Res>
    implements _$ConversationSearchResultCopyWith<$Res> {
  __$ConversationSearchResultCopyWithImpl(this._self, this._then);

  final _ConversationSearchResult _self;
  final $Res Function(_ConversationSearchResult) _then;

/// Create a copy of ConversationSearchResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? conversation = null,Object? matchedMessages = null,}) {
  return _then(_ConversationSearchResult(
conversation: null == conversation ? _self.conversation : conversation // ignore: cast_nullable_to_non_nullable
as Conversation,matchedMessages: null == matchedMessages ? _self._matchedMessages : matchedMessages // ignore: cast_nullable_to_non_nullable
as List<MatchedMessage>,
  ));
}

/// Create a copy of ConversationSearchResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConversationCopyWith<$Res> get conversation {
  
  return $ConversationCopyWith<$Res>(_self.conversation, (value) {
    return _then(_self.copyWith(conversation: value));
  });
}
}


/// @nodoc
mixin _$SearchResults {

 List<ConversationSearchResult> get items; int get total; int get page;@JsonKey(name: 'page_size') int get pageSize; String get query;
/// Create a copy of SearchResults
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SearchResultsCopyWith<SearchResults> get copyWith => _$SearchResultsCopyWithImpl<SearchResults>(this as SearchResults, _$identity);

  /// Serializes this SearchResults to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SearchResults&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.query, query) || other.query == query));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),total,page,pageSize,query);

@override
String toString() {
  return 'SearchResults(items: $items, total: $total, page: $page, pageSize: $pageSize, query: $query)';
}


}

/// @nodoc
abstract mixin class $SearchResultsCopyWith<$Res>  {
  factory $SearchResultsCopyWith(SearchResults value, $Res Function(SearchResults) _then) = _$SearchResultsCopyWithImpl;
@useResult
$Res call({
 List<ConversationSearchResult> items, int total, int page,@JsonKey(name: 'page_size') int pageSize, String query
});




}
/// @nodoc
class _$SearchResultsCopyWithImpl<$Res>
    implements $SearchResultsCopyWith<$Res> {
  _$SearchResultsCopyWithImpl(this._self, this._then);

  final SearchResults _self;
  final $Res Function(SearchResults) _then;

/// Create a copy of SearchResults
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? total = null,Object? page = null,Object? pageSize = null,Object? query = null,}) {
  return _then(SearchResults(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ConversationSearchResult>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SearchResults].
extension SearchResultsPatterns on SearchResults {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SearchResults value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SearchResults() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SearchResults value)  $default,){
final _that = this;
switch (_that) {
case _SearchResults():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SearchResults value)?  $default,){
final _that = this;
switch (_that) {
case _SearchResults() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<ConversationSearchResult> items,  int total,  int page, @JsonKey(name: 'page_size')  int pageSize,  String query)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SearchResults() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.pageSize,_that.query);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<ConversationSearchResult> items,  int total,  int page, @JsonKey(name: 'page_size')  int pageSize,  String query)  $default,) {final _that = this;
switch (_that) {
case _SearchResults():
return $default(_that.items,_that.total,_that.page,_that.pageSize,_that.query);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<ConversationSearchResult> items,  int total,  int page, @JsonKey(name: 'page_size')  int pageSize,  String query)?  $default,) {final _that = this;
switch (_that) {
case _SearchResults() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.pageSize,_that.query);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SearchResults extends SearchResults {
  const _SearchResults({required  List<ConversationSearchResult> items, required this.total, required this.page, @JsonKey(name: 'page_size') required this.pageSize, required this.query}): _items = items,super._();
  factory _SearchResults.fromJson(Map<String, dynamic> json) => _$SearchResultsFromJson(json);

 final  List<ConversationSearchResult> _items;
@override List<ConversationSearchResult> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int total;
@override final  int page;
@override@JsonKey(name: 'page_size') final  int pageSize;
@override final  String query;

/// Create a copy of SearchResults
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SearchResultsCopyWith<_SearchResults> get copyWith => __$SearchResultsCopyWithImpl<_SearchResults>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SearchResultsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SearchResults&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize)&&(identical(other.query, query) || other.query == query));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),total,page,pageSize,query);

@override
String toString() {
  return 'SearchResults(items: $items, total: $total, page: $page, pageSize: $pageSize, query: $query)';
}


}

/// @nodoc
abstract mixin class _$SearchResultsCopyWith<$Res> implements $SearchResultsCopyWith<$Res> {
  factory _$SearchResultsCopyWith(_SearchResults value, $Res Function(_SearchResults) _then) = __$SearchResultsCopyWithImpl;
@override @useResult
$Res call({
 List<ConversationSearchResult> items, int total, int page,@JsonKey(name: 'page_size') int pageSize, String query
});




}
/// @nodoc
class __$SearchResultsCopyWithImpl<$Res>
    implements _$SearchResultsCopyWith<$Res> {
  __$SearchResultsCopyWithImpl(this._self, this._then);

  final _SearchResults _self;
  final $Res Function(_SearchResults) _then;

/// Create a copy of SearchResults
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? total = null,Object? page = null,Object? pageSize = null,Object? query = null,}) {
  return _then(_SearchResults(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ConversationSearchResult>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
