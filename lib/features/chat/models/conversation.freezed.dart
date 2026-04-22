// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

Conversation _$ConversationFromJson(Map<String, dynamic> json) {
  return _Conversation.fromJson(json);
}

/// @nodoc
mixin _$Conversation {
  String get id => throw _privateConstructorUsedError;
  String? get title => throw _privateConstructorUsedError;
  String get model => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime get updatedAt => throw _privateConstructorUsedError;
  int get messageCount => throw _privateConstructorUsedError;
  bool get useMemory => throw _privateConstructorUsedError;
  bool get isPinned => throw _privateConstructorUsedError;
  String? get contextSummary => throw _privateConstructorUsedError;
  String? get systemPrompt => throw _privateConstructorUsedError;
  List<String>? get enabledTools => throw _privateConstructorUsedError;
  List<ChatMessage>? get messages => throw _privateConstructorUsedError;

  /// Serializes this Conversation to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Conversation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ConversationCopyWith<Conversation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConversationCopyWith<$Res> {
  factory $ConversationCopyWith(
    Conversation value,
    $Res Function(Conversation) then,
  ) = _$ConversationCopyWithImpl<$Res, Conversation>;
  @useResult
  $Res call({
    String id,
    String? title,
    String model,
    DateTime createdAt,
    DateTime updatedAt,
    int messageCount,
    bool useMemory,
    bool isPinned,
    String? contextSummary,
    String? systemPrompt,
    List<String>? enabledTools,
    List<ChatMessage>? messages,
  });
}

/// @nodoc
class _$ConversationCopyWithImpl<$Res, $Val extends Conversation>
    implements $ConversationCopyWith<$Res> {
  _$ConversationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Conversation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = freezed,
    Object? model = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? messageCount = null,
    Object? useMemory = null,
    Object? isPinned = null,
    Object? contextSummary = freezed,
    Object? systemPrompt = freezed,
    Object? enabledTools = freezed,
    Object? messages = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            title: freezed == title
                ? _value.title
                : title // ignore: cast_nullable_to_non_nullable
                      as String?,
            model: null == model
                ? _value.model
                : model // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            updatedAt: null == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            messageCount: null == messageCount
                ? _value.messageCount
                : messageCount // ignore: cast_nullable_to_non_nullable
                      as int,
            useMemory: null == useMemory
                ? _value.useMemory
                : useMemory // ignore: cast_nullable_to_non_nullable
                      as bool,
            isPinned: null == isPinned
                ? _value.isPinned
                : isPinned // ignore: cast_nullable_to_non_nullable
                      as bool,
            contextSummary: freezed == contextSummary
                ? _value.contextSummary
                : contextSummary // ignore: cast_nullable_to_non_nullable
                      as String?,
            systemPrompt: freezed == systemPrompt
                ? _value.systemPrompt
                : systemPrompt // ignore: cast_nullable_to_non_nullable
                      as String?,
            enabledTools: freezed == enabledTools
                ? _value.enabledTools
                : enabledTools // ignore: cast_nullable_to_non_nullable
                      as List<String>?,
            messages: freezed == messages
                ? _value.messages
                : messages // ignore: cast_nullable_to_non_nullable
                      as List<ChatMessage>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ConversationImplCopyWith<$Res>
    implements $ConversationCopyWith<$Res> {
  factory _$$ConversationImplCopyWith(
    _$ConversationImpl value,
    $Res Function(_$ConversationImpl) then,
  ) = __$$ConversationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String? title,
    String model,
    DateTime createdAt,
    DateTime updatedAt,
    int messageCount,
    bool useMemory,
    bool isPinned,
    String? contextSummary,
    String? systemPrompt,
    List<String>? enabledTools,
    List<ChatMessage>? messages,
  });
}

/// @nodoc
class __$$ConversationImplCopyWithImpl<$Res>
    extends _$ConversationCopyWithImpl<$Res, _$ConversationImpl>
    implements _$$ConversationImplCopyWith<$Res> {
  __$$ConversationImplCopyWithImpl(
    _$ConversationImpl _value,
    $Res Function(_$ConversationImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Conversation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = freezed,
    Object? model = null,
    Object? createdAt = null,
    Object? updatedAt = null,
    Object? messageCount = null,
    Object? useMemory = null,
    Object? isPinned = null,
    Object? contextSummary = freezed,
    Object? systemPrompt = freezed,
    Object? enabledTools = freezed,
    Object? messages = freezed,
  }) {
    return _then(
      _$ConversationImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        title: freezed == title
            ? _value.title
            : title // ignore: cast_nullable_to_non_nullable
                  as String?,
        model: null == model
            ? _value.model
            : model // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        updatedAt: null == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        messageCount: null == messageCount
            ? _value.messageCount
            : messageCount // ignore: cast_nullable_to_non_nullable
                  as int,
        useMemory: null == useMemory
            ? _value.useMemory
            : useMemory // ignore: cast_nullable_to_non_nullable
                  as bool,
        isPinned: null == isPinned
            ? _value.isPinned
            : isPinned // ignore: cast_nullable_to_non_nullable
                  as bool,
        contextSummary: freezed == contextSummary
            ? _value.contextSummary
            : contextSummary // ignore: cast_nullable_to_non_nullable
                  as String?,
        systemPrompt: freezed == systemPrompt
            ? _value.systemPrompt
            : systemPrompt // ignore: cast_nullable_to_non_nullable
                  as String?,
        enabledTools: freezed == enabledTools
            ? _value._enabledTools
            : enabledTools // ignore: cast_nullable_to_non_nullable
                  as List<String>?,
        messages: freezed == messages
            ? _value._messages
            : messages // ignore: cast_nullable_to_non_nullable
                  as List<ChatMessage>?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ConversationImpl extends _Conversation {
  const _$ConversationImpl({
    required this.id,
    this.title,
    required this.model,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.useMemory = true,
    this.isPinned = false,
    this.contextSummary,
    this.systemPrompt,
    final List<String>? enabledTools,
    final List<ChatMessage>? messages,
  }) : _enabledTools = enabledTools,
       _messages = messages,
       super._();

  factory _$ConversationImpl.fromJson(Map<String, dynamic> json) =>
      _$$ConversationImplFromJson(json);

  @override
  final String id;
  @override
  final String? title;
  @override
  final String model;
  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  @JsonKey()
  final int messageCount;
  @override
  @JsonKey()
  final bool useMemory;
  @override
  @JsonKey()
  final bool isPinned;
  @override
  final String? contextSummary;
  @override
  final String? systemPrompt;
  final List<String>? _enabledTools;
  @override
  List<String>? get enabledTools {
    final value = _enabledTools;
    if (value == null) return null;
    if (_enabledTools is EqualUnmodifiableListView) return _enabledTools;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  final List<ChatMessage>? _messages;
  @override
  List<ChatMessage>? get messages {
    final value = _messages;
    if (value == null) return null;
    if (_messages is EqualUnmodifiableListView) return _messages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  String toString() {
    return 'Conversation(id: $id, title: $title, model: $model, createdAt: $createdAt, updatedAt: $updatedAt, messageCount: $messageCount, useMemory: $useMemory, isPinned: $isPinned, contextSummary: $contextSummary, systemPrompt: $systemPrompt, enabledTools: $enabledTools, messages: $messages)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConversationImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.model, model) || other.model == model) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.messageCount, messageCount) ||
                other.messageCount == messageCount) &&
            (identical(other.useMemory, useMemory) ||
                other.useMemory == useMemory) &&
            (identical(other.isPinned, isPinned) ||
                other.isPinned == isPinned) &&
            (identical(other.contextSummary, contextSummary) ||
                other.contextSummary == contextSummary) &&
            (identical(other.systemPrompt, systemPrompt) ||
                other.systemPrompt == systemPrompt) &&
            const DeepCollectionEquality().equals(
              other._enabledTools,
              _enabledTools,
            ) &&
            const DeepCollectionEquality().equals(other._messages, _messages));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    title,
    model,
    createdAt,
    updatedAt,
    messageCount,
    useMemory,
    isPinned,
    contextSummary,
    systemPrompt,
    const DeepCollectionEquality().hash(_enabledTools),
    const DeepCollectionEquality().hash(_messages),
  );

  /// Create a copy of Conversation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ConversationImplCopyWith<_$ConversationImpl> get copyWith =>
      __$$ConversationImplCopyWithImpl<_$ConversationImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ConversationImplToJson(this);
  }
}

abstract class _Conversation extends Conversation {
  const factory _Conversation({
    required final String id,
    final String? title,
    required final String model,
    required final DateTime createdAt,
    required final DateTime updatedAt,
    final int messageCount,
    final bool useMemory,
    final bool isPinned,
    final String? contextSummary,
    final String? systemPrompt,
    final List<String>? enabledTools,
    final List<ChatMessage>? messages,
  }) = _$ConversationImpl;
  const _Conversation._() : super._();

  factory _Conversation.fromJson(Map<String, dynamic> json) =
      _$ConversationImpl.fromJson;

  @override
  String get id;
  @override
  String? get title;
  @override
  String get model;
  @override
  DateTime get createdAt;
  @override
  DateTime get updatedAt;
  @override
  int get messageCount;
  @override
  bool get useMemory;
  @override
  bool get isPinned;
  @override
  String? get contextSummary;
  @override
  String? get systemPrompt;
  @override
  List<String>? get enabledTools;
  @override
  List<ChatMessage>? get messages;

  /// Create a copy of Conversation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ConversationImplCopyWith<_$ConversationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ConversationList _$ConversationListFromJson(Map<String, dynamic> json) {
  return _ConversationList.fromJson(json);
}

/// @nodoc
mixin _$ConversationList {
  List<Conversation> get items => throw _privateConstructorUsedError;
  int get total => throw _privateConstructorUsedError;
  int get page => throw _privateConstructorUsedError;
  int get pageSize => throw _privateConstructorUsedError;

  /// Serializes this ConversationList to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ConversationList
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ConversationListCopyWith<ConversationList> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConversationListCopyWith<$Res> {
  factory $ConversationListCopyWith(
    ConversationList value,
    $Res Function(ConversationList) then,
  ) = _$ConversationListCopyWithImpl<$Res, ConversationList>;
  @useResult
  $Res call({List<Conversation> items, int total, int page, int pageSize});
}

/// @nodoc
class _$ConversationListCopyWithImpl<$Res, $Val extends ConversationList>
    implements $ConversationListCopyWith<$Res> {
  _$ConversationListCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ConversationList
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? items = null,
    Object? total = null,
    Object? page = null,
    Object? pageSize = null,
  }) {
    return _then(
      _value.copyWith(
            items: null == items
                ? _value.items
                : items // ignore: cast_nullable_to_non_nullable
                      as List<Conversation>,
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
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ConversationListImplCopyWith<$Res>
    implements $ConversationListCopyWith<$Res> {
  factory _$$ConversationListImplCopyWith(
    _$ConversationListImpl value,
    $Res Function(_$ConversationListImpl) then,
  ) = __$$ConversationListImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<Conversation> items, int total, int page, int pageSize});
}

/// @nodoc
class __$$ConversationListImplCopyWithImpl<$Res>
    extends _$ConversationListCopyWithImpl<$Res, _$ConversationListImpl>
    implements _$$ConversationListImplCopyWith<$Res> {
  __$$ConversationListImplCopyWithImpl(
    _$ConversationListImpl _value,
    $Res Function(_$ConversationListImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ConversationList
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? items = null,
    Object? total = null,
    Object? page = null,
    Object? pageSize = null,
  }) {
    return _then(
      _$ConversationListImpl(
        items: null == items
            ? _value._items
            : items // ignore: cast_nullable_to_non_nullable
                  as List<Conversation>,
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
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ConversationListImpl extends _ConversationList {
  const _$ConversationListImpl({
    required final List<Conversation> items,
    required this.total,
    required this.page,
    required this.pageSize,
  }) : _items = items,
       super._();

  factory _$ConversationListImpl.fromJson(Map<String, dynamic> json) =>
      _$$ConversationListImplFromJson(json);

  final List<Conversation> _items;
  @override
  List<Conversation> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  final int total;
  @override
  final int page;
  @override
  final int pageSize;

  @override
  String toString() {
    return 'ConversationList(items: $items, total: $total, page: $page, pageSize: $pageSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConversationListImpl &&
            const DeepCollectionEquality().equals(other._items, _items) &&
            (identical(other.total, total) || other.total == total) &&
            (identical(other.page, page) || other.page == page) &&
            (identical(other.pageSize, pageSize) ||
                other.pageSize == pageSize));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_items),
    total,
    page,
    pageSize,
  );

  /// Create a copy of ConversationList
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ConversationListImplCopyWith<_$ConversationListImpl> get copyWith =>
      __$$ConversationListImplCopyWithImpl<_$ConversationListImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$ConversationListImplToJson(this);
  }
}

abstract class _ConversationList extends ConversationList {
  const factory _ConversationList({
    required final List<Conversation> items,
    required final int total,
    required final int page,
    required final int pageSize,
  }) = _$ConversationListImpl;
  const _ConversationList._() : super._();

  factory _ConversationList.fromJson(Map<String, dynamic> json) =
      _$ConversationListImpl.fromJson;

  @override
  List<Conversation> get items;
  @override
  int get total;
  @override
  int get page;
  @override
  int get pageSize;

  /// Create a copy of ConversationList
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ConversationListImplCopyWith<_$ConversationListImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
