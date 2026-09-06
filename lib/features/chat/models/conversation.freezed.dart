// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Conversation {

 String get id; String? get title; String get model; DateTime get createdAt; DateTime get updatedAt; int get messageCount; bool get useMemory; bool get useKnowledgeBase; bool get isPinned; String? get contextSummary; String? get systemPrompt;@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ThinkingLevel? get thinkingLevel; List<String>? get enabledTools; List<ChatMessage>? get messages; bool get hasMoreMessages; DateTime? get mutedUntil; bool get isPrimary; String? get activeTopicId; TopicNode? get activeTopic; bool get topicIsPinned; int get contextVersion;
/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationCopyWith<Conversation> get copyWith => _$ConversationCopyWithImpl<Conversation>(this as Conversation, _$identity);

  /// Serializes this Conversation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.model, model) || other.model == model)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.messageCount, messageCount) || other.messageCount == messageCount)&&(identical(other.useMemory, useMemory) || other.useMemory == useMemory)&&(identical(other.useKnowledgeBase, useKnowledgeBase) || other.useKnowledgeBase == useKnowledgeBase)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned)&&(identical(other.contextSummary, contextSummary) || other.contextSummary == contextSummary)&&(identical(other.systemPrompt, systemPrompt) || other.systemPrompt == systemPrompt)&&(identical(other.thinkingLevel, thinkingLevel) || other.thinkingLevel == thinkingLevel)&&const DeepCollectionEquality().equals(other.enabledTools, enabledTools)&&const DeepCollectionEquality().equals(other.messages, messages)&&(identical(other.hasMoreMessages, hasMoreMessages) || other.hasMoreMessages == hasMoreMessages)&&(identical(other.mutedUntil, mutedUntil) || other.mutedUntil == mutedUntil)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary)&&(identical(other.activeTopicId, activeTopicId) || other.activeTopicId == activeTopicId)&&(identical(other.activeTopic, activeTopic) || other.activeTopic == activeTopic)&&(identical(other.topicIsPinned, topicIsPinned) || other.topicIsPinned == topicIsPinned)&&(identical(other.contextVersion, contextVersion) || other.contextVersion == contextVersion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,model,createdAt,updatedAt,messageCount,useMemory,useKnowledgeBase,isPinned,contextSummary,systemPrompt,thinkingLevel,const DeepCollectionEquality().hash(enabledTools),const DeepCollectionEquality().hash(messages),hasMoreMessages,mutedUntil,isPrimary,activeTopicId,activeTopic,topicIsPinned,contextVersion]);

@override
String toString() {
  return 'Conversation(id: $id, title: $title, model: $model, createdAt: $createdAt, updatedAt: $updatedAt, messageCount: $messageCount, useMemory: $useMemory, useKnowledgeBase: $useKnowledgeBase, isPinned: $isPinned, contextSummary: $contextSummary, systemPrompt: $systemPrompt, thinkingLevel: $thinkingLevel, enabledTools: $enabledTools, messages: $messages, hasMoreMessages: $hasMoreMessages, mutedUntil: $mutedUntil, isPrimary: $isPrimary, activeTopicId: $activeTopicId, activeTopic: $activeTopic, topicIsPinned: $topicIsPinned, contextVersion: $contextVersion)';
}


}

/// @nodoc
abstract mixin class $ConversationCopyWith<$Res>  {
  factory $ConversationCopyWith(Conversation value, $Res Function(Conversation) _then) = _$ConversationCopyWithImpl;
@useResult
$Res call({
 String id, String? title, String model, DateTime createdAt, DateTime updatedAt, int messageCount, bool useMemory, bool useKnowledgeBase, bool isPinned, String? contextSummary, String? systemPrompt,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ThinkingLevel? thinkingLevel, List<String>? enabledTools, List<ChatMessage>? messages, bool hasMoreMessages, DateTime? mutedUntil, bool isPrimary, String? activeTopicId, TopicNode? activeTopic, bool topicIsPinned, int contextVersion
});




}
/// @nodoc
class _$ConversationCopyWithImpl<$Res>
    implements $ConversationCopyWith<$Res> {
  _$ConversationCopyWithImpl(this._self, this._then);

  final Conversation _self;
  final $Res Function(Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = freezed,Object? model = null,Object? createdAt = null,Object? updatedAt = null,Object? messageCount = null,Object? useMemory = null,Object? useKnowledgeBase = null,Object? isPinned = null,Object? contextSummary = freezed,Object? systemPrompt = freezed,Object? thinkingLevel = freezed,Object? enabledTools = freezed,Object? messages = freezed,Object? hasMoreMessages = null,Object? mutedUntil = freezed,Object? isPrimary = null,Object? activeTopicId = freezed,Object? activeTopic = freezed,Object? topicIsPinned = null,Object? contextVersion = null,}) {
  return _then(Conversation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,messageCount: null == messageCount ? _self.messageCount : messageCount // ignore: cast_nullable_to_non_nullable
as int,useMemory: null == useMemory ? _self.useMemory : useMemory // ignore: cast_nullable_to_non_nullable
as bool,useKnowledgeBase: null == useKnowledgeBase ? _self.useKnowledgeBase : useKnowledgeBase // ignore: cast_nullable_to_non_nullable
as bool,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,contextSummary: freezed == contextSummary ? _self.contextSummary : contextSummary // ignore: cast_nullable_to_non_nullable
as String?,systemPrompt: freezed == systemPrompt ? _self.systemPrompt : systemPrompt // ignore: cast_nullable_to_non_nullable
as String?,thinkingLevel: freezed == thinkingLevel ? _self.thinkingLevel : thinkingLevel // ignore: cast_nullable_to_non_nullable
as ThinkingLevel?,enabledTools: freezed == enabledTools ? _self.enabledTools : enabledTools // ignore: cast_nullable_to_non_nullable
as List<String>?,messages: freezed == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<ChatMessage>?,hasMoreMessages: null == hasMoreMessages ? _self.hasMoreMessages : hasMoreMessages // ignore: cast_nullable_to_non_nullable
as bool,mutedUntil: freezed == mutedUntil ? _self.mutedUntil : mutedUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,activeTopicId: freezed == activeTopicId ? _self.activeTopicId : activeTopicId // ignore: cast_nullable_to_non_nullable
as String?,activeTopic: freezed == activeTopic ? _self.activeTopic : activeTopic // ignore: cast_nullable_to_non_nullable
as TopicNode?,topicIsPinned: null == topicIsPinned ? _self.topicIsPinned : topicIsPinned // ignore: cast_nullable_to_non_nullable
as bool,contextVersion: null == contextVersion ? _self.contextVersion : contextVersion // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Conversation].
extension ConversationPatterns on Conversation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Conversation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Conversation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Conversation value)  $default,){
final _that = this;
switch (_that) {
case _Conversation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Conversation value)?  $default,){
final _that = this;
switch (_that) {
case _Conversation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String? title,  String model,  DateTime createdAt,  DateTime updatedAt,  int messageCount,  bool useMemory,  bool useKnowledgeBase,  bool isPinned,  String? contextSummary,  String? systemPrompt, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ThinkingLevel? thinkingLevel,  List<String>? enabledTools,  List<ChatMessage>? messages,  bool hasMoreMessages,  DateTime? mutedUntil,  bool isPrimary,  String? activeTopicId,  TopicNode? activeTopic,  bool topicIsPinned,  int contextVersion)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.title,_that.model,_that.createdAt,_that.updatedAt,_that.messageCount,_that.useMemory,_that.useKnowledgeBase,_that.isPinned,_that.contextSummary,_that.systemPrompt,_that.thinkingLevel,_that.enabledTools,_that.messages,_that.hasMoreMessages,_that.mutedUntil,_that.isPrimary,_that.activeTopicId,_that.activeTopic,_that.topicIsPinned,_that.contextVersion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String? title,  String model,  DateTime createdAt,  DateTime updatedAt,  int messageCount,  bool useMemory,  bool useKnowledgeBase,  bool isPinned,  String? contextSummary,  String? systemPrompt, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ThinkingLevel? thinkingLevel,  List<String>? enabledTools,  List<ChatMessage>? messages,  bool hasMoreMessages,  DateTime? mutedUntil,  bool isPrimary,  String? activeTopicId,  TopicNode? activeTopic,  bool topicIsPinned,  int contextVersion)  $default,) {final _that = this;
switch (_that) {
case _Conversation():
return $default(_that.id,_that.title,_that.model,_that.createdAt,_that.updatedAt,_that.messageCount,_that.useMemory,_that.useKnowledgeBase,_that.isPinned,_that.contextSummary,_that.systemPrompt,_that.thinkingLevel,_that.enabledTools,_that.messages,_that.hasMoreMessages,_that.mutedUntil,_that.isPrimary,_that.activeTopicId,_that.activeTopic,_that.topicIsPinned,_that.contextVersion);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String? title,  String model,  DateTime createdAt,  DateTime updatedAt,  int messageCount,  bool useMemory,  bool useKnowledgeBase,  bool isPinned,  String? contextSummary,  String? systemPrompt, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ThinkingLevel? thinkingLevel,  List<String>? enabledTools,  List<ChatMessage>? messages,  bool hasMoreMessages,  DateTime? mutedUntil,  bool isPrimary,  String? activeTopicId,  TopicNode? activeTopic,  bool topicIsPinned,  int contextVersion)?  $default,) {final _that = this;
switch (_that) {
case _Conversation() when $default != null:
return $default(_that.id,_that.title,_that.model,_that.createdAt,_that.updatedAt,_that.messageCount,_that.useMemory,_that.useKnowledgeBase,_that.isPinned,_that.contextSummary,_that.systemPrompt,_that.thinkingLevel,_that.enabledTools,_that.messages,_that.hasMoreMessages,_that.mutedUntil,_that.isPrimary,_that.activeTopicId,_that.activeTopic,_that.topicIsPinned,_that.contextVersion);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Conversation extends Conversation {
  const _Conversation({required this.id, this.title, required this.model, required this.createdAt, required this.updatedAt, this.messageCount = 0, this.useMemory = true, this.useKnowledgeBase = true, this.isPinned = false, this.contextSummary, this.systemPrompt, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) this.thinkingLevel,  List<String>? enabledTools,  List<ChatMessage>? messages, this.hasMoreMessages = false, this.mutedUntil, this.isPrimary = false, this.activeTopicId, this.activeTopic, this.topicIsPinned = false, this.contextVersion = 0}): _enabledTools = enabledTools,_messages = messages,super._();
  factory _Conversation.fromJson(Map<String, dynamic> json) => _$ConversationFromJson(json);

@override final  String id;
@override final  String? title;
@override final  String model;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;
@override@JsonKey() final  int messageCount;
@override@JsonKey() final  bool useMemory;
@override@JsonKey() final  bool useKnowledgeBase;
@override@JsonKey() final  bool isPinned;
@override final  String? contextSummary;
@override final  String? systemPrompt;
@override@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) final  ThinkingLevel? thinkingLevel;
 final  List<String>? _enabledTools;
@override List<String>? get enabledTools {
  final value = _enabledTools;
  if (value == null) return null;
  if (_enabledTools is EqualUnmodifiableListView) return _enabledTools;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<ChatMessage>? _messages;
@override List<ChatMessage>? get messages {
  final value = _messages;
  if (value == null) return null;
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override@JsonKey() final  bool hasMoreMessages;
@override final  DateTime? mutedUntil;
@override@JsonKey() final  bool isPrimary;
@override final  String? activeTopicId;
@override final  TopicNode? activeTopic;
@override@JsonKey() final  bool topicIsPinned;
@override@JsonKey() final  int contextVersion;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationCopyWith<_Conversation> get copyWith => __$ConversationCopyWithImpl<_Conversation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Conversation&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.model, model) || other.model == model)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.messageCount, messageCount) || other.messageCount == messageCount)&&(identical(other.useMemory, useMemory) || other.useMemory == useMemory)&&(identical(other.useKnowledgeBase, useKnowledgeBase) || other.useKnowledgeBase == useKnowledgeBase)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned)&&(identical(other.contextSummary, contextSummary) || other.contextSummary == contextSummary)&&(identical(other.systemPrompt, systemPrompt) || other.systemPrompt == systemPrompt)&&(identical(other.thinkingLevel, thinkingLevel) || other.thinkingLevel == thinkingLevel)&&const DeepCollectionEquality().equals(other._enabledTools, _enabledTools)&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.hasMoreMessages, hasMoreMessages) || other.hasMoreMessages == hasMoreMessages)&&(identical(other.mutedUntil, mutedUntil) || other.mutedUntil == mutedUntil)&&(identical(other.isPrimary, isPrimary) || other.isPrimary == isPrimary)&&(identical(other.activeTopicId, activeTopicId) || other.activeTopicId == activeTopicId)&&(identical(other.activeTopic, activeTopic) || other.activeTopic == activeTopic)&&(identical(other.topicIsPinned, topicIsPinned) || other.topicIsPinned == topicIsPinned)&&(identical(other.contextVersion, contextVersion) || other.contextVersion == contextVersion));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hashAll([runtimeType,id,title,model,createdAt,updatedAt,messageCount,useMemory,useKnowledgeBase,isPinned,contextSummary,systemPrompt,thinkingLevel,const DeepCollectionEquality().hash(_enabledTools),const DeepCollectionEquality().hash(_messages),hasMoreMessages,mutedUntil,isPrimary,activeTopicId,activeTopic,topicIsPinned,contextVersion]);

@override
String toString() {
  return 'Conversation(id: $id, title: $title, model: $model, createdAt: $createdAt, updatedAt: $updatedAt, messageCount: $messageCount, useMemory: $useMemory, useKnowledgeBase: $useKnowledgeBase, isPinned: $isPinned, contextSummary: $contextSummary, systemPrompt: $systemPrompt, thinkingLevel: $thinkingLevel, enabledTools: $enabledTools, messages: $messages, hasMoreMessages: $hasMoreMessages, mutedUntil: $mutedUntil, isPrimary: $isPrimary, activeTopicId: $activeTopicId, activeTopic: $activeTopic, topicIsPinned: $topicIsPinned, contextVersion: $contextVersion)';
}


}

/// @nodoc
abstract mixin class _$ConversationCopyWith<$Res> implements $ConversationCopyWith<$Res> {
  factory _$ConversationCopyWith(_Conversation value, $Res Function(_Conversation) _then) = __$ConversationCopyWithImpl;
@override @useResult
$Res call({
 String id, String? title, String model, DateTime createdAt, DateTime updatedAt, int messageCount, bool useMemory, bool useKnowledgeBase, bool isPinned, String? contextSummary, String? systemPrompt,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ThinkingLevel? thinkingLevel, List<String>? enabledTools, List<ChatMessage>? messages, bool hasMoreMessages, DateTime? mutedUntil, bool isPrimary, String? activeTopicId, TopicNode? activeTopic, bool topicIsPinned, int contextVersion
});




}
/// @nodoc
class __$ConversationCopyWithImpl<$Res>
    implements _$ConversationCopyWith<$Res> {
  __$ConversationCopyWithImpl(this._self, this._then);

  final _Conversation _self;
  final $Res Function(_Conversation) _then;

/// Create a copy of Conversation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = freezed,Object? model = null,Object? createdAt = null,Object? updatedAt = null,Object? messageCount = null,Object? useMemory = null,Object? useKnowledgeBase = null,Object? isPinned = null,Object? contextSummary = freezed,Object? systemPrompt = freezed,Object? thinkingLevel = freezed,Object? enabledTools = freezed,Object? messages = freezed,Object? hasMoreMessages = null,Object? mutedUntil = freezed,Object? isPrimary = null,Object? activeTopicId = freezed,Object? activeTopic = freezed,Object? topicIsPinned = null,Object? contextVersion = null,}) {
  return _then(_Conversation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,messageCount: null == messageCount ? _self.messageCount : messageCount // ignore: cast_nullable_to_non_nullable
as int,useMemory: null == useMemory ? _self.useMemory : useMemory // ignore: cast_nullable_to_non_nullable
as bool,useKnowledgeBase: null == useKnowledgeBase ? _self.useKnowledgeBase : useKnowledgeBase // ignore: cast_nullable_to_non_nullable
as bool,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,contextSummary: freezed == contextSummary ? _self.contextSummary : contextSummary // ignore: cast_nullable_to_non_nullable
as String?,systemPrompt: freezed == systemPrompt ? _self.systemPrompt : systemPrompt // ignore: cast_nullable_to_non_nullable
as String?,thinkingLevel: freezed == thinkingLevel ? _self.thinkingLevel : thinkingLevel // ignore: cast_nullable_to_non_nullable
as ThinkingLevel?,enabledTools: freezed == enabledTools ? _self._enabledTools : enabledTools // ignore: cast_nullable_to_non_nullable
as List<String>?,messages: freezed == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<ChatMessage>?,hasMoreMessages: null == hasMoreMessages ? _self.hasMoreMessages : hasMoreMessages // ignore: cast_nullable_to_non_nullable
as bool,mutedUntil: freezed == mutedUntil ? _self.mutedUntil : mutedUntil // ignore: cast_nullable_to_non_nullable
as DateTime?,isPrimary: null == isPrimary ? _self.isPrimary : isPrimary // ignore: cast_nullable_to_non_nullable
as bool,activeTopicId: freezed == activeTopicId ? _self.activeTopicId : activeTopicId // ignore: cast_nullable_to_non_nullable
as String?,activeTopic: freezed == activeTopic ? _self.activeTopic : activeTopic // ignore: cast_nullable_to_non_nullable
as TopicNode?,topicIsPinned: null == topicIsPinned ? _self.topicIsPinned : topicIsPinned // ignore: cast_nullable_to_non_nullable
as bool,contextVersion: null == contextVersion ? _self.contextVersion : contextVersion // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ConversationList {

 List<Conversation> get items; int get total; int get page; int get pageSize;
/// Create a copy of ConversationList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationListCopyWith<ConversationList> get copyWith => _$ConversationListCopyWithImpl<ConversationList>(this as ConversationList, _$identity);

  /// Serializes this ConversationList to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationList&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(items),total,page,pageSize);

@override
String toString() {
  return 'ConversationList(items: $items, total: $total, page: $page, pageSize: $pageSize)';
}


}

/// @nodoc
abstract mixin class $ConversationListCopyWith<$Res>  {
  factory $ConversationListCopyWith(ConversationList value, $Res Function(ConversationList) _then) = _$ConversationListCopyWithImpl;
@useResult
$Res call({
 List<Conversation> items, int total, int page, int pageSize
});




}
/// @nodoc
class _$ConversationListCopyWithImpl<$Res>
    implements $ConversationListCopyWith<$Res> {
  _$ConversationListCopyWithImpl(this._self, this._then);

  final ConversationList _self;
  final $Res Function(ConversationList) _then;

/// Create a copy of ConversationList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? items = null,Object? total = null,Object? page = null,Object? pageSize = null,}) {
  return _then(ConversationList(
items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<Conversation>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationList].
extension ConversationListPatterns on ConversationList {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationList value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationList() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationList value)  $default,){
final _that = this;
switch (_that) {
case _ConversationList():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationList value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationList() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Conversation> items,  int total,  int page,  int pageSize)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationList() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.pageSize);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Conversation> items,  int total,  int page,  int pageSize)  $default,) {final _that = this;
switch (_that) {
case _ConversationList():
return $default(_that.items,_that.total,_that.page,_that.pageSize);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Conversation> items,  int total,  int page,  int pageSize)?  $default,) {final _that = this;
switch (_that) {
case _ConversationList() when $default != null:
return $default(_that.items,_that.total,_that.page,_that.pageSize);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ConversationList extends ConversationList {
  const _ConversationList({required  List<Conversation> items, required this.total, required this.page, required this.pageSize}): _items = items,super._();
  factory _ConversationList.fromJson(Map<String, dynamic> json) => _$ConversationListFromJson(json);

 final  List<Conversation> _items;
@override List<Conversation> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int total;
@override final  int page;
@override final  int pageSize;

/// Create a copy of ConversationList
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationListCopyWith<_ConversationList> get copyWith => __$ConversationListCopyWithImpl<_ConversationList>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConversationListToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationList&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.total, total) || other.total == total)&&(identical(other.page, page) || other.page == page)&&(identical(other.pageSize, pageSize) || other.pageSize == pageSize));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_items),total,page,pageSize);

@override
String toString() {
  return 'ConversationList(items: $items, total: $total, page: $page, pageSize: $pageSize)';
}


}

/// @nodoc
abstract mixin class _$ConversationListCopyWith<$Res> implements $ConversationListCopyWith<$Res> {
  factory _$ConversationListCopyWith(_ConversationList value, $Res Function(_ConversationList) _then) = __$ConversationListCopyWithImpl;
@override @useResult
$Res call({
 List<Conversation> items, int total, int page, int pageSize
});




}
/// @nodoc
class __$ConversationListCopyWithImpl<$Res>
    implements _$ConversationListCopyWith<$Res> {
  __$ConversationListCopyWithImpl(this._self, this._then);

  final _ConversationList _self;
  final $Res Function(_ConversationList) _then;

/// Create a copy of ConversationList
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? items = null,Object? total = null,Object? page = null,Object? pageSize = null,}) {
  return _then(_ConversationList(
items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<Conversation>,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,page: null == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as int,pageSize: null == pageSize ? _self.pageSize : pageSize // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
