// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'style.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Style {

 String get id; String get name; String get modelId;@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ThinkingLevel? get thinkingLevel; String? get systemPromptTemplateId; bool get isDefault; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Style
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StyleCopyWith<Style> get copyWith => _$StyleCopyWithImpl<Style>(this as Style, _$identity);

  /// Serializes this Style to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Style&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.thinkingLevel, thinkingLevel) || other.thinkingLevel == thinkingLevel)&&(identical(other.systemPromptTemplateId, systemPromptTemplateId) || other.systemPromptTemplateId == systemPromptTemplateId)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,modelId,thinkingLevel,systemPromptTemplateId,isDefault,createdAt,updatedAt);

@override
String toString() {
  return 'Style(id: $id, name: $name, modelId: $modelId, thinkingLevel: $thinkingLevel, systemPromptTemplateId: $systemPromptTemplateId, isDefault: $isDefault, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $StyleCopyWith<$Res>  {
  factory $StyleCopyWith(Style value, $Res Function(Style) _then) = _$StyleCopyWithImpl;
@useResult
$Res call({
 String id, String name, String modelId,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ThinkingLevel? thinkingLevel, String? systemPromptTemplateId, bool isDefault, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$StyleCopyWithImpl<$Res>
    implements $StyleCopyWith<$Res> {
  _$StyleCopyWithImpl(this._self, this._then);

  final Style _self;
  final $Res Function(Style) _then;

/// Create a copy of Style
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? modelId = null,Object? thinkingLevel = freezed,Object? systemPromptTemplateId = freezed,Object? isDefault = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(Style(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,thinkingLevel: freezed == thinkingLevel ? _self.thinkingLevel : thinkingLevel // ignore: cast_nullable_to_non_nullable
as ThinkingLevel?,systemPromptTemplateId: freezed == systemPromptTemplateId ? _self.systemPromptTemplateId : systemPromptTemplateId // ignore: cast_nullable_to_non_nullable
as String?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Style].
extension StylePatterns on Style {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Style value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Style() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Style value)  $default,){
final _that = this;
switch (_that) {
case _Style():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Style value)?  $default,){
final _that = this;
switch (_that) {
case _Style() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String modelId, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ThinkingLevel? thinkingLevel,  String? systemPromptTemplateId,  bool isDefault,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Style() when $default != null:
return $default(_that.id,_that.name,_that.modelId,_that.thinkingLevel,_that.systemPromptTemplateId,_that.isDefault,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String modelId, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ThinkingLevel? thinkingLevel,  String? systemPromptTemplateId,  bool isDefault,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Style():
return $default(_that.id,_that.name,_that.modelId,_that.thinkingLevel,_that.systemPromptTemplateId,_that.isDefault,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String modelId, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ThinkingLevel? thinkingLevel,  String? systemPromptTemplateId,  bool isDefault,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Style() when $default != null:
return $default(_that.id,_that.name,_that.modelId,_that.thinkingLevel,_that.systemPromptTemplateId,_that.isDefault,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Style implements Style {
  const _Style({required this.id, required this.name, required this.modelId, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) this.thinkingLevel, this.systemPromptTemplateId, this.isDefault = false, required this.createdAt, required this.updatedAt});
  factory _Style.fromJson(Map<String, dynamic> json) => _$StyleFromJson(json);

@override final  String id;
@override final  String name;
@override final  String modelId;
@override@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) final  ThinkingLevel? thinkingLevel;
@override final  String? systemPromptTemplateId;
@override@JsonKey() final  bool isDefault;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Style
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StyleCopyWith<_Style> get copyWith => __$StyleCopyWithImpl<_Style>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$StyleToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Style&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.thinkingLevel, thinkingLevel) || other.thinkingLevel == thinkingLevel)&&(identical(other.systemPromptTemplateId, systemPromptTemplateId) || other.systemPromptTemplateId == systemPromptTemplateId)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,modelId,thinkingLevel,systemPromptTemplateId,isDefault,createdAt,updatedAt);

@override
String toString() {
  return 'Style(id: $id, name: $name, modelId: $modelId, thinkingLevel: $thinkingLevel, systemPromptTemplateId: $systemPromptTemplateId, isDefault: $isDefault, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$StyleCopyWith<$Res> implements $StyleCopyWith<$Res> {
  factory _$StyleCopyWith(_Style value, $Res Function(_Style) _then) = __$StyleCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String modelId,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ThinkingLevel? thinkingLevel, String? systemPromptTemplateId, bool isDefault, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$StyleCopyWithImpl<$Res>
    implements _$StyleCopyWith<$Res> {
  __$StyleCopyWithImpl(this._self, this._then);

  final _Style _self;
  final $Res Function(_Style) _then;

/// Create a copy of Style
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? modelId = null,Object? thinkingLevel = freezed,Object? systemPromptTemplateId = freezed,Object? isDefault = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Style(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,thinkingLevel: freezed == thinkingLevel ? _self.thinkingLevel : thinkingLevel // ignore: cast_nullable_to_non_nullable
as ThinkingLevel?,systemPromptTemplateId: freezed == systemPromptTemplateId ? _self.systemPromptTemplateId : systemPromptTemplateId // ignore: cast_nullable_to_non_nullable
as String?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
