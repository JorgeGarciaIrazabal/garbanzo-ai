// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_info.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

ModelInfo _$ModelInfoFromJson(Map<String, dynamic> json) {
  return _ModelInfo.fromJson(json);
}

/// @nodoc
mixin _$ModelInfo {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  int? get contextLength => throw _privateConstructorUsedError;
  String get provider => throw _privateConstructorUsedError;

  /// Serializes this ModelInfo to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ModelInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ModelInfoCopyWith<ModelInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ModelInfoCopyWith<$Res> {
  factory $ModelInfoCopyWith(ModelInfo value, $Res Function(ModelInfo) then) =
      _$ModelInfoCopyWithImpl<$Res, ModelInfo>;
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    int? contextLength,
    String provider,
  });
}

/// @nodoc
class _$ModelInfoCopyWithImpl<$Res, $Val extends ModelInfo>
    implements $ModelInfoCopyWith<$Res> {
  _$ModelInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ModelInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? contextLength = freezed,
    Object? provider = null,
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
            contextLength: freezed == contextLength
                ? _value.contextLength
                : contextLength // ignore: cast_nullable_to_non_nullable
                      as int?,
            provider: null == provider
                ? _value.provider
                : provider // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ModelInfoImplCopyWith<$Res>
    implements $ModelInfoCopyWith<$Res> {
  factory _$$ModelInfoImplCopyWith(
    _$ModelInfoImpl value,
    $Res Function(_$ModelInfoImpl) then,
  ) = __$$ModelInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? description,
    int? contextLength,
    String provider,
  });
}

/// @nodoc
class __$$ModelInfoImplCopyWithImpl<$Res>
    extends _$ModelInfoCopyWithImpl<$Res, _$ModelInfoImpl>
    implements _$$ModelInfoImplCopyWith<$Res> {
  __$$ModelInfoImplCopyWithImpl(
    _$ModelInfoImpl _value,
    $Res Function(_$ModelInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ModelInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? description = freezed,
    Object? contextLength = freezed,
    Object? provider = null,
  }) {
    return _then(
      _$ModelInfoImpl(
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
        contextLength: freezed == contextLength
            ? _value.contextLength
            : contextLength // ignore: cast_nullable_to_non_nullable
                  as int?,
        provider: null == provider
            ? _value.provider
            : provider // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ModelInfoImpl implements _ModelInfo {
  const _$ModelInfoImpl({
    required this.id,
    required this.name,
    this.description,
    this.contextLength,
    required this.provider,
  });

  factory _$ModelInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$ModelInfoImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? description;
  @override
  final int? contextLength;
  @override
  final String provider;

  @override
  String toString() {
    return 'ModelInfo(id: $id, name: $name, description: $description, contextLength: $contextLength, provider: $provider)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ModelInfoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.contextLength, contextLength) ||
                other.contextLength == contextLength) &&
            (identical(other.provider, provider) ||
                other.provider == provider));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, name, description, contextLength, provider);

  /// Create a copy of ModelInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ModelInfoImplCopyWith<_$ModelInfoImpl> get copyWith =>
      __$$ModelInfoImplCopyWithImpl<_$ModelInfoImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ModelInfoImplToJson(this);
  }
}

abstract class _ModelInfo implements ModelInfo {
  const factory _ModelInfo({
    required final String id,
    required final String name,
    final String? description,
    final int? contextLength,
    required final String provider,
  }) = _$ModelInfoImpl;

  factory _ModelInfo.fromJson(Map<String, dynamic> json) =
      _$ModelInfoImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get description;
  @override
  int? get contextLength;
  @override
  String get provider;

  /// Create a copy of ModelInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ModelInfoImplCopyWith<_$ModelInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ModelList _$ModelListFromJson(Map<String, dynamic> json) {
  return _ModelList.fromJson(json);
}

/// @nodoc
mixin _$ModelList {
  List<ModelInfo> get models => throw _privateConstructorUsedError;

  /// Serializes this ModelList to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ModelList
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ModelListCopyWith<ModelList> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ModelListCopyWith<$Res> {
  factory $ModelListCopyWith(ModelList value, $Res Function(ModelList) then) =
      _$ModelListCopyWithImpl<$Res, ModelList>;
  @useResult
  $Res call({List<ModelInfo> models});
}

/// @nodoc
class _$ModelListCopyWithImpl<$Res, $Val extends ModelList>
    implements $ModelListCopyWith<$Res> {
  _$ModelListCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ModelList
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? models = null}) {
    return _then(
      _value.copyWith(
            models: null == models
                ? _value.models
                : models // ignore: cast_nullable_to_non_nullable
                      as List<ModelInfo>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ModelListImplCopyWith<$Res>
    implements $ModelListCopyWith<$Res> {
  factory _$$ModelListImplCopyWith(
    _$ModelListImpl value,
    $Res Function(_$ModelListImpl) then,
  ) = __$$ModelListImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({List<ModelInfo> models});
}

/// @nodoc
class __$$ModelListImplCopyWithImpl<$Res>
    extends _$ModelListCopyWithImpl<$Res, _$ModelListImpl>
    implements _$$ModelListImplCopyWith<$Res> {
  __$$ModelListImplCopyWithImpl(
    _$ModelListImpl _value,
    $Res Function(_$ModelListImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ModelList
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? models = null}) {
    return _then(
      _$ModelListImpl(
        models: null == models
            ? _value._models
            : models // ignore: cast_nullable_to_non_nullable
                  as List<ModelInfo>,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ModelListImpl implements _ModelList {
  const _$ModelListImpl({required final List<ModelInfo> models})
    : _models = models;

  factory _$ModelListImpl.fromJson(Map<String, dynamic> json) =>
      _$$ModelListImplFromJson(json);

  final List<ModelInfo> _models;
  @override
  List<ModelInfo> get models {
    if (_models is EqualUnmodifiableListView) return _models;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_models);
  }

  @override
  String toString() {
    return 'ModelList(models: $models)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ModelListImpl &&
            const DeepCollectionEquality().equals(other._models, _models));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_models));

  /// Create a copy of ModelList
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ModelListImplCopyWith<_$ModelListImpl> get copyWith =>
      __$$ModelListImplCopyWithImpl<_$ModelListImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ModelListImplToJson(this);
  }
}

abstract class _ModelList implements ModelList {
  const factory _ModelList({required final List<ModelInfo> models}) =
      _$ModelListImpl;

  factory _ModelList.fromJson(Map<String, dynamic> json) =
      _$ModelListImpl.fromJson;

  @override
  List<ModelInfo> get models;

  /// Create a copy of ModelList
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ModelListImplCopyWith<_$ModelListImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
