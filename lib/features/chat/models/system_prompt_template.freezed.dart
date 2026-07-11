// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'system_prompt_template.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SystemPromptTemplate {

 String get id; String get name; String? get description; String get content; bool get isBuiltin; DateTime get createdAt;
/// Create a copy of SystemPromptTemplate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SystemPromptTemplateCopyWith<SystemPromptTemplate> get copyWith => _$SystemPromptTemplateCopyWithImpl<SystemPromptTemplate>(this as SystemPromptTemplate, _$identity);

  /// Serializes this SystemPromptTemplate to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SystemPromptTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.content, content) || other.content == content)&&(identical(other.isBuiltin, isBuiltin) || other.isBuiltin == isBuiltin)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,content,isBuiltin,createdAt);

@override
String toString() {
  return 'SystemPromptTemplate(id: $id, name: $name, description: $description, content: $content, isBuiltin: $isBuiltin, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $SystemPromptTemplateCopyWith<$Res>  {
  factory $SystemPromptTemplateCopyWith(SystemPromptTemplate value, $Res Function(SystemPromptTemplate) _then) = _$SystemPromptTemplateCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, String content, bool isBuiltin, DateTime createdAt
});




}
/// @nodoc
class _$SystemPromptTemplateCopyWithImpl<$Res>
    implements $SystemPromptTemplateCopyWith<$Res> {
  _$SystemPromptTemplateCopyWithImpl(this._self, this._then);

  final SystemPromptTemplate _self;
  final $Res Function(SystemPromptTemplate) _then;

/// Create a copy of SystemPromptTemplate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? content = null,Object? isBuiltin = null,Object? createdAt = null,}) {
  return _then(SystemPromptTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,isBuiltin: null == isBuiltin ? _self.isBuiltin : isBuiltin // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SystemPromptTemplate].
extension SystemPromptTemplatePatterns on SystemPromptTemplate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SystemPromptTemplate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SystemPromptTemplate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SystemPromptTemplate value)  $default,){
final _that = this;
switch (_that) {
case _SystemPromptTemplate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SystemPromptTemplate value)?  $default,){
final _that = this;
switch (_that) {
case _SystemPromptTemplate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String content,  bool isBuiltin,  DateTime createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SystemPromptTemplate() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.content,_that.isBuiltin,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  String content,  bool isBuiltin,  DateTime createdAt)  $default,) {final _that = this;
switch (_that) {
case _SystemPromptTemplate():
return $default(_that.id,_that.name,_that.description,_that.content,_that.isBuiltin,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  String content,  bool isBuiltin,  DateTime createdAt)?  $default,) {final _that = this;
switch (_that) {
case _SystemPromptTemplate() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.content,_that.isBuiltin,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SystemPromptTemplate extends SystemPromptTemplate {
  const _SystemPromptTemplate({required this.id, required this.name, this.description, required this.content, this.isBuiltin = false, required this.createdAt}): super._();
  factory _SystemPromptTemplate.fromJson(Map<String, dynamic> json) => _$SystemPromptTemplateFromJson(json);

@override final  String id;
@override final  String name;
@override final  String? description;
@override final  String content;
@override@JsonKey() final  bool isBuiltin;
@override final  DateTime createdAt;

/// Create a copy of SystemPromptTemplate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SystemPromptTemplateCopyWith<_SystemPromptTemplate> get copyWith => __$SystemPromptTemplateCopyWithImpl<_SystemPromptTemplate>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SystemPromptTemplateToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SystemPromptTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.content, content) || other.content == content)&&(identical(other.isBuiltin, isBuiltin) || other.isBuiltin == isBuiltin)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,content,isBuiltin,createdAt);

@override
String toString() {
  return 'SystemPromptTemplate(id: $id, name: $name, description: $description, content: $content, isBuiltin: $isBuiltin, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$SystemPromptTemplateCopyWith<$Res> implements $SystemPromptTemplateCopyWith<$Res> {
  factory _$SystemPromptTemplateCopyWith(_SystemPromptTemplate value, $Res Function(_SystemPromptTemplate) _then) = __$SystemPromptTemplateCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, String content, bool isBuiltin, DateTime createdAt
});




}
/// @nodoc
class __$SystemPromptTemplateCopyWithImpl<$Res>
    implements _$SystemPromptTemplateCopyWith<$Res> {
  __$SystemPromptTemplateCopyWithImpl(this._self, this._then);

  final _SystemPromptTemplate _self;
  final $Res Function(_SystemPromptTemplate) _then;

/// Create a copy of SystemPromptTemplate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? content = null,Object? isBuiltin = null,Object? createdAt = null,}) {
  return _then(_SystemPromptTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,isBuiltin: null == isBuiltin ? _self.isBuiltin : isBuiltin // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
