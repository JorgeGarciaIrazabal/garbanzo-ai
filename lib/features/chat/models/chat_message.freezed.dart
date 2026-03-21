// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) {
  return _ChatMessage.fromJson(json);
}

/// @nodoc
mixin _$ChatMessage {
  String get id => throw _privateConstructorUsedError;
  String get role => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  @JsonKey(readValue: _readMetadata)
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<ChatAttachment> get attachments => throw _privateConstructorUsedError;

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatMessageCopyWith<ChatMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatMessageCopyWith<$Res> {
  factory $ChatMessageCopyWith(
    ChatMessage value,
    $Res Function(ChatMessage) then,
  ) = _$ChatMessageCopyWithImpl<$Res, ChatMessage>;
  @useResult
  $Res call({
    String id,
    String role,
    String content,
    DateTime createdAt,
    @JsonKey(readValue: _readMetadata) Map<String, dynamic>? metadata,
    @JsonKey(includeFromJson: false, includeToJson: false)
    List<ChatAttachment> attachments,
  });
}

/// @nodoc
class _$ChatMessageCopyWithImpl<$Res, $Val extends ChatMessage>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? createdAt = null,
    Object? metadata = freezed,
    Object? attachments = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            role: null == role
                ? _value.role
                : role // ignore: cast_nullable_to_non_nullable
                      as String,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            metadata: freezed == metadata
                ? _value.metadata
                : metadata // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>?,
            attachments: null == attachments
                ? _value.attachments
                : attachments // ignore: cast_nullable_to_non_nullable
                      as List<ChatAttachment>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatMessageImplCopyWith<$Res>
    implements $ChatMessageCopyWith<$Res> {
  factory _$$ChatMessageImplCopyWith(
    _$ChatMessageImpl value,
    $Res Function(_$ChatMessageImpl) then,
  ) = __$$ChatMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String role,
    String content,
    DateTime createdAt,
    @JsonKey(readValue: _readMetadata) Map<String, dynamic>? metadata,
    @JsonKey(includeFromJson: false, includeToJson: false)
    List<ChatAttachment> attachments,
  });
}

/// @nodoc
class __$$ChatMessageImplCopyWithImpl<$Res>
    extends _$ChatMessageCopyWithImpl<$Res, _$ChatMessageImpl>
    implements _$$ChatMessageImplCopyWith<$Res> {
  __$$ChatMessageImplCopyWithImpl(
    _$ChatMessageImpl _value,
    $Res Function(_$ChatMessageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? createdAt = null,
    Object? metadata = freezed,
    Object? attachments = null,
  }) {
    return _then(
      _$ChatMessageImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        role: null == role
            ? _value.role
            : role // ignore: cast_nullable_to_non_nullable
                  as String,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        metadata: freezed == metadata
            ? _value._metadata
            : metadata // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>?,
        attachments: null == attachments
            ? _value._attachments
            : attachments // ignore: cast_nullable_to_non_nullable
                  as List<ChatAttachment>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ChatMessageImpl extends _ChatMessage {
  const _$ChatMessageImpl({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    @JsonKey(readValue: _readMetadata) final Map<String, dynamic>? metadata,
    @JsonKey(includeFromJson: false, includeToJson: false)
    final List<ChatAttachment> attachments = const [],
  }) : _metadata = metadata,
       _attachments = attachments,
       super._();

  factory _$ChatMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChatMessageImplFromJson(json);

  @override
  final String id;
  @override
  final String role;
  @override
  final String content;
  @override
  final DateTime createdAt;
  final Map<String, dynamic>? _metadata;
  @override
  @JsonKey(readValue: _readMetadata)
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  final List<ChatAttachment> _attachments;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<ChatAttachment> get attachments {
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_attachments);
  }

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, content: $content, createdAt: $createdAt, metadata: $metadata, attachments: $attachments)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatMessageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata) &&
            const DeepCollectionEquality().equals(
              other._attachments,
              _attachments,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    role,
    content,
    createdAt,
    const DeepCollectionEquality().hash(_metadata),
    const DeepCollectionEquality().hash(_attachments),
  );

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      __$$ChatMessageImplCopyWithImpl<_$ChatMessageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChatMessageImplToJson(this);
  }
}

abstract class _ChatMessage extends ChatMessage {
  const factory _ChatMessage({
    required final String id,
    required final String role,
    required final String content,
    required final DateTime createdAt,
    @JsonKey(readValue: _readMetadata) final Map<String, dynamic>? metadata,
    @JsonKey(includeFromJson: false, includeToJson: false)
    final List<ChatAttachment> attachments,
  }) = _$ChatMessageImpl;
  const _ChatMessage._() : super._();

  factory _ChatMessage.fromJson(Map<String, dynamic> json) =
      _$ChatMessageImpl.fromJson;

  @override
  String get id;
  @override
  String get role;
  @override
  String get content;
  @override
  DateTime get createdAt;
  @override
  @JsonKey(readValue: _readMetadata)
  Map<String, dynamic>? get metadata;
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  List<ChatAttachment> get attachments;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ChatResponseChunk _$ChatResponseChunkFromJson(Map<String, dynamic> json) {
  return _ChatResponseChunk.fromJson(json);
}

/// @nodoc
mixin _$ChatResponseChunk {
  String get type => throw _privateConstructorUsedError;
  String? get content => throw _privateConstructorUsedError;
  String? get error => throw _privateConstructorUsedError;
  Map<String, dynamic>? get metadata => throw _privateConstructorUsedError;

  /// Serializes this ChatResponseChunk to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatResponseChunkCopyWith<ChatResponseChunk> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatResponseChunkCopyWith<$Res> {
  factory $ChatResponseChunkCopyWith(
    ChatResponseChunk value,
    $Res Function(ChatResponseChunk) then,
  ) = _$ChatResponseChunkCopyWithImpl<$Res, ChatResponseChunk>;
  @useResult
  $Res call({
    String type,
    String? content,
    String? error,
    Map<String, dynamic>? metadata,
  });
}

/// @nodoc
class _$ChatResponseChunkCopyWithImpl<$Res, $Val extends ChatResponseChunk>
    implements $ChatResponseChunkCopyWith<$Res> {
  _$ChatResponseChunkCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? content = freezed,
    Object? error = freezed,
    Object? metadata = freezed,
  }) {
    return _then(
      _value.copyWith(
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String,
            content: freezed == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String?,
            error: freezed == error
                ? _value.error
                : error // ignore: cast_nullable_to_non_nullable
                      as String?,
            metadata: freezed == metadata
                ? _value.metadata
                : metadata // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatResponseChunkImplCopyWith<$Res>
    implements $ChatResponseChunkCopyWith<$Res> {
  factory _$$ChatResponseChunkImplCopyWith(
    _$ChatResponseChunkImpl value,
    $Res Function(_$ChatResponseChunkImpl) then,
  ) = __$$ChatResponseChunkImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String type,
    String? content,
    String? error,
    Map<String, dynamic>? metadata,
  });
}

/// @nodoc
class __$$ChatResponseChunkImplCopyWithImpl<$Res>
    extends _$ChatResponseChunkCopyWithImpl<$Res, _$ChatResponseChunkImpl>
    implements _$$ChatResponseChunkImplCopyWith<$Res> {
  __$$ChatResponseChunkImplCopyWithImpl(
    _$ChatResponseChunkImpl _value,
    $Res Function(_$ChatResponseChunkImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? content = freezed,
    Object? error = freezed,
    Object? metadata = freezed,
  }) {
    return _then(
      _$ChatResponseChunkImpl(
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
        content: freezed == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String?,
        error: freezed == error
            ? _value.error
            : error // ignore: cast_nullable_to_non_nullable
                  as String?,
        metadata: freezed == metadata
            ? _value._metadata
            : metadata // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ChatResponseChunkImpl extends _ChatResponseChunk {
  const _$ChatResponseChunkImpl({
    required this.type,
    this.content,
    this.error,
    final Map<String, dynamic>? metadata,
  }) : _metadata = metadata,
       super._();

  factory _$ChatResponseChunkImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChatResponseChunkImplFromJson(json);

  @override
  final String type;
  @override
  final String? content;
  @override
  final String? error;
  final Map<String, dynamic>? _metadata;
  @override
  Map<String, dynamic>? get metadata {
    final value = _metadata;
    if (value == null) return null;
    if (_metadata is EqualUnmodifiableMapView) return _metadata;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'ChatResponseChunk(type: $type, content: $content, error: $error, metadata: $metadata)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatResponseChunkImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.error, error) || other.error == error) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    type,
    content,
    error,
    const DeepCollectionEquality().hash(_metadata),
  );

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatResponseChunkImplCopyWith<_$ChatResponseChunkImpl> get copyWith =>
      __$$ChatResponseChunkImplCopyWithImpl<_$ChatResponseChunkImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$ChatResponseChunkImplToJson(this);
  }
}

abstract class _ChatResponseChunk extends ChatResponseChunk {
  const factory _ChatResponseChunk({
    required final String type,
    final String? content,
    final String? error,
    final Map<String, dynamic>? metadata,
  }) = _$ChatResponseChunkImpl;
  const _ChatResponseChunk._() : super._();

  factory _ChatResponseChunk.fromJson(Map<String, dynamic> json) =
      _$ChatResponseChunkImpl.fromJson;

  @override
  String get type;
  @override
  String? get content;
  @override
  String? get error;
  @override
  Map<String, dynamic>? get metadata;

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatResponseChunkImplCopyWith<_$ChatResponseChunkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
