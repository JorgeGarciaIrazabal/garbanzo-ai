// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'system_prompt_template.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

SystemPromptTemplate _$SystemPromptTemplateFromJson(Map<String, dynamic> json) {
  return _SystemPromptTemplate.fromJson(json);
}

/// @nodoc
mixin _$SystemPromptTemplate {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  bool get isBuiltin => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this SystemPromptTemplate to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SystemPromptTemplate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SystemPromptTemplateCopyWith<SystemPromptTemplate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SystemPromptTemplateCopyWith<$Res> {
  factory $SystemPromptTemplateCopyWith(
    SystemPromptTemplate value,
    $Res Function(SystemPromptTemplate) then,
  ) = _$SystemPromptTemplateCopyWithImpl<$Res, SystemPromptTemplate>;
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    String content,
    bool isBuiltin,
    DateTime createdAt,
  });
}

/// @nodoc
class _$SystemPromptTemplateCopyWithImpl<
  $Res,
  $Val extends SystemPromptTemplate
>
    implements $SystemPromptTemplateCopyWith<$Res> {
  _$SystemPromptTemplateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SystemPromptTemplate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? content = null,
    Object? isBuiltin = null,
    Object? createdAt = null,
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
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            isBuiltin: null == isBuiltin
                ? _value.isBuiltin
                : isBuiltin // ignore: cast_nullable_to_non_nullable
                      as bool,
            createdAt: null == createdAt
                ? _value.createdAt
                : createdAt // ignore: cast_nullable_to_non_nullable
                      as DateTime,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SystemPromptTemplateImplCopyWith<$Res>
    implements $SystemPromptTemplateCopyWith<$Res> {
  factory _$$SystemPromptTemplateImplCopyWith(
    _$SystemPromptTemplateImpl value,
    $Res Function(_$SystemPromptTemplateImpl) then,
  ) = __$$SystemPromptTemplateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    String content,
    bool isBuiltin,
    DateTime createdAt,
  });
}

/// @nodoc
class __$$SystemPromptTemplateImplCopyWithImpl<$Res>
    extends _$SystemPromptTemplateCopyWithImpl<$Res, _$SystemPromptTemplateImpl>
    implements _$$SystemPromptTemplateImplCopyWith<$Res> {
  __$$SystemPromptTemplateImplCopyWithImpl(
    _$SystemPromptTemplateImpl _value,
    $Res Function(_$SystemPromptTemplateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SystemPromptTemplate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? content = null,
    Object? isBuiltin = null,
    Object? createdAt = null,
  }) {
    return _then(
      _$SystemPromptTemplateImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        isBuiltin: null == isBuiltin
            ? _value.isBuiltin
            : isBuiltin // ignore: cast_nullable_to_non_nullable
                  as bool,
        createdAt: null == createdAt
            ? _value.createdAt
            : createdAt // ignore: cast_nullable_to_non_nullable
                  as DateTime,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SystemPromptTemplateImpl extends _SystemPromptTemplate {
  const _$SystemPromptTemplateImpl({
    required this.id,
    required this.name,
    this.description,
    required this.content,
    this.isBuiltin = false,
    required this.createdAt,
  }) : super._();

  factory _$SystemPromptTemplateImpl.fromJson(Map<String, dynamic> json) =>
      _$$SystemPromptTemplateImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? description;
  @override
  final String content;
  @override
  @JsonKey()
  final bool isBuiltin;
  @override
  final DateTime createdAt;

  @override
  String toString() {
    return 'SystemPromptTemplate(id: $id, name: $name, description: $description, content: $content, isBuiltin: $isBuiltin, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SystemPromptTemplateImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.isBuiltin, isBuiltin) ||
                other.isBuiltin == isBuiltin) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    description,
    content,
    isBuiltin,
    createdAt,
  );

  /// Create a copy of SystemPromptTemplate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SystemPromptTemplateImplCopyWith<_$SystemPromptTemplateImpl>
  get copyWith =>
      __$$SystemPromptTemplateImplCopyWithImpl<_$SystemPromptTemplateImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$SystemPromptTemplateImplToJson(this);
  }
}

abstract class _SystemPromptTemplate extends SystemPromptTemplate {
  const factory _SystemPromptTemplate({
    required final String id,
    required final String name,
    final String? description,
    required final String content,
    final bool isBuiltin,
    required final DateTime createdAt,
  }) = _$SystemPromptTemplateImpl;
  const _SystemPromptTemplate._() : super._();

  factory _SystemPromptTemplate.fromJson(Map<String, dynamic> json) =
      _$SystemPromptTemplateImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get description;
  @override
  String get content;
  @override
  bool get isBuiltin;
  @override
  DateTime get createdAt;

  /// Create a copy of SystemPromptTemplate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SystemPromptTemplateImplCopyWith<_$SystemPromptTemplateImpl>
  get copyWith => throw _privateConstructorUsedError;
}
