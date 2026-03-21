// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_attachment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ChatAttachment {
  String get name => throw _privateConstructorUsedError;
  String get mimeType => throw _privateConstructorUsedError;
  AttachmentType get type => throw _privateConstructorUsedError;
  Uint8List get bytes => throw _privateConstructorUsedError;

  /// Create a copy of ChatAttachment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatAttachmentCopyWith<ChatAttachment> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatAttachmentCopyWith<$Res> {
  factory $ChatAttachmentCopyWith(
    ChatAttachment value,
    $Res Function(ChatAttachment) then,
  ) = _$ChatAttachmentCopyWithImpl<$Res, ChatAttachment>;
  @useResult
  $Res call({
    String name,
    String mimeType,
    AttachmentType type,
    Uint8List bytes,
  });
}

/// @nodoc
class _$ChatAttachmentCopyWithImpl<$Res, $Val extends ChatAttachment>
    implements $ChatAttachmentCopyWith<$Res> {
  _$ChatAttachmentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatAttachment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? mimeType = null,
    Object? type = null,
    Object? bytes = null,
  }) {
    return _then(
      _value.copyWith(
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            mimeType: null == mimeType
                ? _value.mimeType
                : mimeType // ignore: cast_nullable_to_non_nullable
                      as String,
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as AttachmentType,
            bytes: null == bytes
                ? _value.bytes
                : bytes // ignore: cast_nullable_to_non_nullable
                      as Uint8List,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatAttachmentImplCopyWith<$Res>
    implements $ChatAttachmentCopyWith<$Res> {
  factory _$$ChatAttachmentImplCopyWith(
    _$ChatAttachmentImpl value,
    $Res Function(_$ChatAttachmentImpl) then,
  ) = __$$ChatAttachmentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String name,
    String mimeType,
    AttachmentType type,
    Uint8List bytes,
  });
}

/// @nodoc
class __$$ChatAttachmentImplCopyWithImpl<$Res>
    extends _$ChatAttachmentCopyWithImpl<$Res, _$ChatAttachmentImpl>
    implements _$$ChatAttachmentImplCopyWith<$Res> {
  __$$ChatAttachmentImplCopyWithImpl(
    _$ChatAttachmentImpl _value,
    $Res Function(_$ChatAttachmentImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatAttachment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? mimeType = null,
    Object? type = null,
    Object? bytes = null,
  }) {
    return _then(
      _$ChatAttachmentImpl(
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        mimeType: null == mimeType
            ? _value.mimeType
            : mimeType // ignore: cast_nullable_to_non_nullable
                  as String,
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as AttachmentType,
        bytes: null == bytes
            ? _value.bytes
            : bytes // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
      ),
    );
  }
}

/// @nodoc

class _$ChatAttachmentImpl extends _ChatAttachment {
  const _$ChatAttachmentImpl({
    required this.name,
    required this.mimeType,
    required this.type,
    required this.bytes,
  }) : super._();

  @override
  final String name;
  @override
  final String mimeType;
  @override
  final AttachmentType type;
  @override
  final Uint8List bytes;

  @override
  String toString() {
    return 'ChatAttachment(name: $name, mimeType: $mimeType, type: $type, bytes: $bytes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatAttachmentImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.mimeType, mimeType) ||
                other.mimeType == mimeType) &&
            (identical(other.type, type) || other.type == type) &&
            const DeepCollectionEquality().equals(other.bytes, bytes));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    name,
    mimeType,
    type,
    const DeepCollectionEquality().hash(bytes),
  );

  /// Create a copy of ChatAttachment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatAttachmentImplCopyWith<_$ChatAttachmentImpl> get copyWith =>
      __$$ChatAttachmentImplCopyWithImpl<_$ChatAttachmentImpl>(
        this,
        _$identity,
      );
}

abstract class _ChatAttachment extends ChatAttachment {
  const factory _ChatAttachment({
    required final String name,
    required final String mimeType,
    required final AttachmentType type,
    required final Uint8List bytes,
  }) = _$ChatAttachmentImpl;
  const _ChatAttachment._() : super._();

  @override
  String get name;
  @override
  String get mimeType;
  @override
  AttachmentType get type;
  @override
  Uint8List get bytes;

  /// Create a copy of ChatAttachment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatAttachmentImplCopyWith<_$ChatAttachmentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
