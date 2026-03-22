// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'memory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

Memory _$MemoryFromJson(Map<String, dynamic> json) {
  return _Memory.fromJson(json);
}

/// @nodoc
mixin _$Memory {
  String get id => throw _privateConstructorUsedError;
  String get userId => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  String? get sourceConversationId => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  bool get isActive => throw _privateConstructorUsedError;

  /// Serializes this Memory to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Memory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MemoryCopyWith<Memory> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MemoryCopyWith<$Res> {
  factory $MemoryCopyWith(Memory value, $Res Function(Memory) then) =
      _$MemoryCopyWithImpl<$Res, Memory>;
  @useResult
  $Res call({
    String id,
    String userId,
    String content,
    String? sourceConversationId,
    DateTime createdAt,
    bool isActive,
  });
}

/// @nodoc
class _$MemoryCopyWithImpl<$Res, $Val extends Memory>
    implements $MemoryCopyWith<$Res> {
  _$MemoryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Memory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? content = null,
    Object? sourceConversationId = freezed,
    Object? createdAt = null,
    Object? isActive = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            userId: null == userId
                ? _value.userId
                : userId // ignore: cast_nullable_to_non_nullable
                      as String,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            sourceConversationId: freezed == sourceConversationId
                ? _value.sourceConversationId
                : sourceConversationId // ignore: cast_nullable_to_non_nullable
                      as String?,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            isActive: null == isActive
                ? _value.isActive
                : isActive // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MemoryImplCopyWith<$Res> implements $MemoryCopyWith<$Res> {
  factory _$$MemoryImplCopyWith(
    _$MemoryImpl value,
    $Res Function(_$MemoryImpl) then,
  ) = __$$MemoryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String userId,
    String content,
    String? sourceConversationId,
    DateTime createdAt,
    bool isActive,
  });
}

/// @nodoc
class __$$MemoryImplCopyWithImpl<$Res>
    extends _$MemoryCopyWithImpl<$Res, _$MemoryImpl>
    implements _$$MemoryImplCopyWith<$Res> {
  __$$MemoryImplCopyWithImpl(
    _$MemoryImpl _value,
    $Res Function(_$MemoryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Memory
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? userId = null,
    Object? content = null,
    Object? sourceConversationId = freezed,
    Object? createdAt = null,
    Object? isActive = null,
  }) {
    return _then(
      _$MemoryImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        userId: null == userId
            ? _value.userId
            : userId // ignore: cast_nullable_to_non_nullable
                  as String,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        sourceConversationId: freezed == sourceConversationId
            ? _value.sourceConversationId
            : sourceConversationId // ignore: cast_nullable_to_non_nullable
                  as String?,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        isActive: null == isActive
            ? _value.isActive
            : isActive // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$MemoryImpl extends _Memory {
  const _$MemoryImpl({
    required this.id,
    required this.userId,
    required this.content,
    this.sourceConversationId,
    required this.createdAt,
    required this.isActive,
  }) : super._();

  factory _$MemoryImpl.fromJson(Map<String, dynamic> json) =>
      _$$MemoryImplFromJson(json);

  @override
  final String id;
  @override
  final String userId;
  @override
  final String content;
  @override
  final String? sourceConversationId;
  @override
  final DateTime createdAt;
  @override
  final bool isActive;

  @override
  String toString() {
    return 'Memory(id: $id, userId: $userId, content: $content, sourceConversationId: $sourceConversationId, createdAt: $createdAt, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MemoryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.sourceConversationId, sourceConversationId) ||
                other.sourceConversationId == sourceConversationId) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    userId,
    content,
    sourceConversationId,
    createdAt,
    isActive,
  );

  /// Create a copy of Memory
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MemoryImplCopyWith<_$MemoryImpl> get copyWith =>
      __$$MemoryImplCopyWithImpl<_$MemoryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MemoryImplToJson(this);
  }
}

abstract class _Memory extends Memory {
  const factory _Memory({
    required final String id,
    required final String userId,
    required final String content,
    final String? sourceConversationId,
    required final DateTime createdAt,
    required final bool isActive,
  }) = _$MemoryImpl;
  const _Memory._() : super._();

  factory _Memory.fromJson(Map<String, dynamic> json) = _$MemoryImpl.fromJson;

  @override
  String get id;
  @override
  String get userId;
  @override
  String get content;
  @override
  String? get sourceConversationId;
  @override
  DateTime get createdAt;
  @override
  bool get isActive;

  /// Create a copy of Memory
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MemoryImplCopyWith<_$MemoryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$MemoryList {
  List<Memory> get items => throw _privateConstructorUsedError;

  /// Create a copy of MemoryList
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MemoryListCopyWith<MemoryList> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MemoryListCopyWith<$Res> {
  factory $MemoryListCopyWith(
    MemoryList value,
    $Res Function(MemoryList) then,
  ) = _$MemoryListCopyWithImpl<$Res, MemoryList>;
  @useResult
  $Res call({List<Memory> items});
}

/// @nodoc
class _$MemoryListCopyWithImpl<$Res, $Val extends MemoryList>
    implements $MemoryListCopyWith<$Res> {
  _$MemoryListCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MemoryList
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? items = null}) {
    return _then(
      _value.copyWith(
            items: null == items
                ? _value.items
                : items // ignore: cast_nullable_to_non_nullable
                      as List<Memory>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MemoryListImplCopyWith<$Res>
    implements $MemoryListCopyWith<$Res> {
  factory _$$MemoryListImplCopyWith(
    _$MemoryListImpl value,
    $Res Function(_$MemoryListImpl) then,
  ) = __$$MemoryListImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<Memory> items});
}

/// @nodoc
class __$$MemoryListImplCopyWithImpl<$Res>
    extends _$MemoryListCopyWithImpl<$Res, _$MemoryListImpl>
    implements _$$MemoryListImplCopyWith<$Res> {
  __$$MemoryListImplCopyWithImpl(
    _$MemoryListImpl _value,
    $Res Function(_$MemoryListImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MemoryList
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? items = null}) {
    return _then(
      _$MemoryListImpl(
        items: null == items
            ? _value._items
            : items // ignore: cast_nullable_to_non_nullable
                  as List<Memory>,
      ),
    );
  }
}

/// @nodoc

class _$MemoryListImpl extends _MemoryList {
  const _$MemoryListImpl({required final List<Memory> items})
    : _items = items,
      super._();

  final List<Memory> _items;
  @override
  List<Memory> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  String toString() {
    return 'MemoryList(items: $items)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MemoryListImpl &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_items));

  /// Create a copy of MemoryList
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MemoryListImplCopyWith<_$MemoryListImpl> get copyWith =>
      __$$MemoryListImplCopyWithImpl<_$MemoryListImpl>(this, _$identity);
}

abstract class _MemoryList extends MemoryList {
  const factory _MemoryList({required final List<Memory> items}) =
      _$MemoryListImpl;
  const _MemoryList._() : super._();

  @override
  List<Memory> get items;

  /// Create a copy of MemoryList
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MemoryListImplCopyWith<_$MemoryListImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
