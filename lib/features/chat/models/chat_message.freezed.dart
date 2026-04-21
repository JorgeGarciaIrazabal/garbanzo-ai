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

ToolCall _$ToolCallFromJson(Map<String, dynamic> json) {
  return _ToolCall.fromJson(json);
}

/// @nodoc
mixin _$ToolCall {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  Map<String, dynamic>? get arguments => throw _privateConstructorUsedError;

  /// Serializes this ToolCall to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ToolCall
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToolCallCopyWith<ToolCall> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToolCallCopyWith<$Res> {
  factory $ToolCallCopyWith(ToolCall value, $Res Function(ToolCall) then) =
      _$ToolCallCopyWithImpl<$Res, ToolCall>;
  @useResult
  $Res call({String id, String name, Map<String, dynamic>? arguments});
}

/// @nodoc
class _$ToolCallCopyWithImpl<$Res, $Val extends ToolCall>
    implements $ToolCallCopyWith<$Res> {
  _$ToolCallCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToolCall
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? arguments = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            arguments: freezed == arguments
                ? _value.arguments
                : arguments // ignore: cast_nullable_to_non_nullable
                      as Map<String, dynamic>?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ToolCallImplCopyWith<$Res>
    implements $ToolCallCopyWith<$Res> {
  factory _$$ToolCallImplCopyWith(
    _$ToolCallImpl value,
    $Res Function(_$ToolCallImpl) then,
  ) = __$$ToolCallImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String name, Map<String, dynamic>? arguments});
}

/// @nodoc
class __$$ToolCallImplCopyWithImpl<$Res>
    extends _$ToolCallCopyWithImpl<$Res, _$ToolCallImpl>
    implements _$$ToolCallImplCopyWith<$Res> {
  __$$ToolCallImplCopyWithImpl(
    _$ToolCallImpl _value,
    $Res Function(_$ToolCallImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ToolCall
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? arguments = freezed,
  }) {
    return _then(
      _$ToolCallImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        arguments: freezed == arguments
            ? _value._arguments
            : arguments // ignore: cast_nullable_to_non_nullable
                  as Map<String, dynamic>?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolCallImpl extends _ToolCall {
  const _$ToolCallImpl({
    required this.id,
    required this.name,
    final Map<String, dynamic>? arguments,
  }) : _arguments = arguments,
       super._();

  factory _$ToolCallImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolCallImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  final Map<String, dynamic>? _arguments;
  @override
  Map<String, dynamic>? get arguments {
    final value = _arguments;
    if (value == null) return null;
    if (_arguments is EqualUnmodifiableMapView) return _arguments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'ToolCall(id: $id, name: $name, arguments: $arguments)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolCallImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality().equals(
              other._arguments,
              _arguments,
            ));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    const DeepCollectionEquality().hash(_arguments),
  );

  /// Create a copy of ToolCall
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolCallImplCopyWith<_$ToolCallImpl> get copyWith =>
      __$$ToolCallImplCopyWithImpl<_$ToolCallImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolCallImplToJson(this);
  }
}

abstract class _ToolCall extends ToolCall {
  const factory _ToolCall({
    required final String id,
    required final String name,
    final Map<String, dynamic>? arguments,
  }) = _$ToolCallImpl;
  const _ToolCall._() : super._();

  factory _ToolCall.fromJson(Map<String, dynamic> json) =
      _$ToolCallImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  Map<String, dynamic>? get arguments;

  /// Create a copy of ToolCall
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToolCallImplCopyWith<_$ToolCallImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ToolResult _$ToolResultFromJson(Map<String, dynamic> json) {
  return _ToolResult.fromJson(json);
}

/// @nodoc
mixin _$ToolResult {
  String get toolCallId => throw _privateConstructorUsedError;
  String get toolName => throw _privateConstructorUsedError;
  dynamic get result => throw _privateConstructorUsedError;

  /// Serializes this ToolResult to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ToolResultCopyWith<ToolResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ToolResultCopyWith<$Res> {
  factory $ToolResultCopyWith(
    ToolResult value,
    $Res Function(ToolResult) then,
  ) = _$ToolResultCopyWithImpl<$Res, ToolResult>;
  @useResult
  $Res call({String toolCallId, String toolName, dynamic result});
}

/// @nodoc
class _$ToolResultCopyWithImpl<$Res, $Val extends ToolResult>
    implements $ToolResultCopyWith<$Res> {
  _$ToolResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? toolCallId = null,
    Object? toolName = null,
    Object? result = freezed,
  }) {
    return _then(
      _value.copyWith(
            toolCallId: null == toolCallId
                ? _value.toolCallId
                : toolCallId // ignore: cast_nullable_to_non_nullable
                      as String,
            toolName: null == toolName
                ? _value.toolName
                : toolName // ignore: cast_nullable_to_non_nullable
                      as String,
            result: freezed == result
                ? _value.result
                : result // ignore: cast_nullable_to_non_nullable
                      as dynamic,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ToolResultImplCopyWith<$Res>
    implements $ToolResultCopyWith<$Res> {
  factory _$$ToolResultImplCopyWith(
    _$ToolResultImpl value,
    $Res Function(_$ToolResultImpl) then,
  ) = __$$ToolResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String toolCallId, String toolName, dynamic result});
}

/// @nodoc
class __$$ToolResultImplCopyWithImpl<$Res>
    extends _$ToolResultCopyWithImpl<$Res, _$ToolResultImpl>
    implements _$$ToolResultImplCopyWith<$Res> {
  __$$ToolResultImplCopyWithImpl(
    _$ToolResultImpl _value,
    $Res Function(_$ToolResultImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? toolCallId = null,
    Object? toolName = null,
    Object? result = freezed,
  }) {
    return _then(
      _$ToolResultImpl(
        toolCallId: null == toolCallId
            ? _value.toolCallId
            : toolCallId // ignore: cast_nullable_to_non_nullable
                  as String,
        toolName: null == toolName
            ? _value.toolName
            : toolName // ignore: cast_nullable_to_non_nullable
                  as String,
        result: freezed == result
            ? _value.result
            : result // ignore: cast_nullable_to_non_nullable
                  as dynamic,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ToolResultImpl extends _ToolResult {
  const _$ToolResultImpl({
    required this.toolCallId,
    required this.toolName,
    this.result,
  }) : super._();

  factory _$ToolResultImpl.fromJson(Map<String, dynamic> json) =>
      _$$ToolResultImplFromJson(json);

  @override
  final String toolCallId;
  @override
  final String toolName;
  @override
  final dynamic result;

  @override
  String toString() {
    return 'ToolResult(toolCallId: $toolCallId, toolName: $toolName, result: $result)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ToolResultImpl &&
            (identical(other.toolCallId, toolCallId) ||
                other.toolCallId == toolCallId) &&
            (identical(other.toolName, toolName) ||
                other.toolName == toolName) &&
            const DeepCollectionEquality().equals(other.result, result));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    toolCallId,
    toolName,
    const DeepCollectionEquality().hash(result),
  );

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ToolResultImplCopyWith<_$ToolResultImpl> get copyWith =>
      __$$ToolResultImplCopyWithImpl<_$ToolResultImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ToolResultImplToJson(this);
  }
}

abstract class _ToolResult extends ToolResult {
  const factory _ToolResult({
    required final String toolCallId,
    required final String toolName,
    final dynamic result,
  }) = _$ToolResultImpl;
  const _ToolResult._() : super._();

  factory _ToolResult.fromJson(Map<String, dynamic> json) =
      _$ToolResultImpl.fromJson;

  @override
  String get toolCallId;
  @override
  String get toolName;
  @override
  dynamic get result;

  /// Create a copy of ToolResult
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ToolResultImplCopyWith<_$ToolResultImpl> get copyWith =>
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
  List<ToolCall>? get toolCalls => throw _privateConstructorUsedError;
  ToolResult? get toolResult => throw _privateConstructorUsedError;

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
    List<ToolCall>? toolCalls,
    ToolResult? toolResult,
  });

  $ToolResultCopyWith<$Res>? get toolResult;
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
    Object? toolCalls = freezed,
    Object? toolResult = freezed,
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
            toolCalls: freezed == toolCalls
                ? _value.toolCalls
                : toolCalls // ignore: cast_nullable_to_non_nullable
                      as List<ToolCall>?,
            toolResult: freezed == toolResult
                ? _value.toolResult
                : toolResult // ignore: cast_nullable_to_non_nullable
                      as ToolResult?,
          )
          as $Val,
    );
  }

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ToolResultCopyWith<$Res>? get toolResult {
    if (_value.toolResult == null) {
      return null;
    }

    return $ToolResultCopyWith<$Res>(_value.toolResult!, (value) {
      return _then(_value.copyWith(toolResult: value) as $Val);
    });
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
    List<ToolCall>? toolCalls,
    ToolResult? toolResult,
  });

  @override
  $ToolResultCopyWith<$Res>? get toolResult;
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
    Object? toolCalls = freezed,
    Object? toolResult = freezed,
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
        toolCalls: freezed == toolCalls
            ? _value._toolCalls
            : toolCalls // ignore: cast_nullable_to_non_nullable
                  as List<ToolCall>?,
        toolResult: freezed == toolResult
            ? _value.toolResult
            : toolResult // ignore: cast_nullable_to_non_nullable
                  as ToolResult?,
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
    final List<ToolCall>? toolCalls,
    this.toolResult,
  }) : _metadata = metadata,
       _toolCalls = toolCalls,
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

  final List<ToolCall>? _toolCalls;
  @override
  List<ToolCall>? get toolCalls {
    final value = _toolCalls;
    if (value == null) return null;
    if (_toolCalls is EqualUnmodifiableListView) return _toolCalls;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  final ToolResult? toolResult;

  @override
  String toString() {
    return 'ChatResponseChunk(type: $type, content: $content, error: $error, metadata: $metadata, toolCalls: $toolCalls, toolResult: $toolResult)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatResponseChunkImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.error, error) || other.error == error) &&
            const DeepCollectionEquality().equals(other._metadata, _metadata) &&
            const DeepCollectionEquality().equals(
              other._toolCalls,
              _toolCalls,
            ) &&
            (identical(other.toolResult, toolResult) ||
                other.toolResult == toolResult));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    type,
    content,
    error,
    const DeepCollectionEquality().hash(_metadata),
    const DeepCollectionEquality().hash(_toolCalls),
    toolResult,
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
    final List<ToolCall>? toolCalls,
    final ToolResult? toolResult,
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
  @override
  List<ToolCall>? get toolCalls;
  @override
  ToolResult? get toolResult;

  /// Create a copy of ChatResponseChunk
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatResponseChunkImplCopyWith<_$ChatResponseChunkImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
